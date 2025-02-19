# frozen_string_literal: true

require "yaml"
require "uri"

require "aurora/aux_heat"
require "aurora/blower"
require "aurora/compressor"
require "aurora/dhw"
require "aurora/humidistat"
require "aurora/iz2_zone"
require "aurora/pump"
require "aurora/thermostat"

module Aurora
  class ABCClient
    class << self
      def open_modbus_slave(uri, ignore_missing_registers: false)
        uri = URI.parse(uri)

        io = case uri.scheme
             when "tcp"
               require "socket"
               TCPSocket.new(uri.host, uri.port)
             when "telnet", "rfc2217"
               require "net/telnet/rfc2217"
               Net::Telnet::RFC2217.new(uri.host,
                                        port: uri.port || 23,
                                        baud: 19_200,
                                        parity: :even)
             when "mqtt", "mqtts"
               require "aurora/mqtt_modbus"
               return Aurora::MQTTModBus.new(uri)
             else
               if File.file?(uri.path)
                 return Aurora::MockABC.new(YAML.load_file(uri.path),
                                            ignore_missing_registers: ignore_missing_registers)
               end

               require "ccutrer-serialport"
               CCutrer::SerialPort.new(uri.path, baud: 19_200, parity: :even)
             end

        client = ::ModBus::RTUClient.new(io)
        client.with_slave(1)
      end

      def query_registers(modbus_slave, query, try_individual: false)
        implicit = try_individual
        ranges = query.split(",").map do |addr|
          case addr
          when "known"
            implicit = true
            try_individual = true if try_individual.nil?
            Aurora::REGISTER_NAMES.keys
          when "valid"
            implicit = true
            try_individual = true if try_individual.nil?
            break Aurora::REGISTER_RANGES
          when "all"
            implicit = true
            try_individual = true if try_individual.nil?
            break 0..65_535
          when /^(\d+)(?:\.\.|-)(\d+)$/
            $1.to_i..$2.to_i
          else
            addr.to_i
          end
        end
        queries = Aurora.normalize_ranges(ranges)
        registers = {}
        last_log_time = nil
        queries.each do |subquery|
          last_log_time = log_query(last_log_time, subquery.inspect)
          registers.merge!(modbus_slave.read_multiple_holding_registers(*subquery))
        rescue ::ModBus::Errors::IllegalDataAddress, ::ModBus::Errors::IllegalFunction, ::ModBus::Errors::ModBusTimeout
          # maybe this unit doesn't respond to all the addresses we want?
          raise unless implicit

          # try each query individually
          subquery.each do |subsubquery|
            last_log_time = log_query(last_log_time, subsubquery.inspect)
            registers.merge!(modbus_slave.read_multiple_holding_registers(subsubquery))
          rescue ::ModBus::Errors::IllegalDataAddress,
                 ::ModBus::Errors::IllegalFunction,
                 ::ModBus::Errors::ModBusTimeout => e
            raise if e.is_a?(::ModBus::Errors::ModBusTimeout) && !try_individual
            next unless try_individual

            # seriously?? try each register individually
            Array(subsubquery).each do |i|
              last_log_time = log_query(last_log_time, i.to_s)
              registers[i] = modbus_slave.holding_registers[i]
            rescue ::ModBus::Errors::IllegalDataAddress, ::ModBus::Errors::IllegalFunction
              # don't catch ModBusTimeout here... it should have no problem responding to a single register request
              next
            end
          end
        end
        registers
      end

      private

      def log_query(last_log_time, query)
        last_log_time ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if now - last_log_time > 5
          Aurora.logger&.info("Fetching register(s) #{query}...")
          last_log_time = now
        end
        last_log_time
      end
    end

    attr_reader :modbus_slave,
                :abc_version,
                :model,
                :serial_number,
                :zones,
                :aux_heat,
                :compressor,
                :blower,
                :pump,
                :dhw,
                :humidistat,
                :current_fault,
                :faults,
                :locked_out,
                :derated,
                :safe_mode,
                :current_mode,
                :low_pressure_switch,
                :high_pressure_switch,
                :emergency_shutdown,
                :load_shed,
                :entering_air_temperature,
                :leaving_air_temperature,
                :leaving_water_temperature,
                :entering_water_temperature,
                :outdoor_temperature,
                :air_coil_temperature,
                :line_voltage,
                :line_voltage_setting,
                :watts

    alias_method :emergency_shutdown?, :emergency_shutdown
    alias_method :load_shed?, :load_shed
    alias_method :locked_out?, :locked_out
    alias_method :derated?, :derated
    alias_method :safe_mode?, :safe_mode

    def initialize(uri)
      @modbus_slave = self.class.open_modbus_slave(uri)
      @modbus_slave.read_retry_timeout = 15
      @modbus_slave.read_retries = 2
      raw_registers = @modbus_slave.holding_registers[2, 33, 88...110, 404, 412..413, 813, 1103, 1114]
      registers = Aurora.transform_registers(raw_registers.dup)
      @abc_version = registers[2]
      @program = registers[88]
      @model = registers[92]
      @serial_number = registers[105]
      @energy_monitor = raw_registers[412]

      @zones = if iz2? && iz2_version >= 2.0
                 iz2_zone_count = @modbus_slave.holding_registers[483]
                 (0...iz2_zone_count).map { |i| IZ2Zone.new(self, i + 1) }
               else
                 [Thermostat.new(self)]
               end

      @abc_dipswitches = registers[33]
      @axb_dipswitches = registers[1103]
      @aux_heat = AuxHeat.new(self)
      @compressor = if %w[ABCVSP ABCSPLVS].include?(@program)
                      Compressor::VSDrive.new(self)
                    else
                      Compressor::GenericCompressor.new(self,
                                                        @abc_dipswitches[:compressor])
                    end
      @blower = case raw_registers[404]
                when 1, 2 then Blower::ECM.new(self, registers[404])
                when 3 then Blower::FiveSpeed.new(self, registers[404])
                else; Blower::PSC.new(self, registers[404])
                end
      @pump = if (3..5).cover?(raw_registers[413])
                Pump::VSPump.new(self,
                                 registers[413])
              elsif axb?
                Pump::GenericPump.new(self,
                                      registers[413])
              end
      @dhw = DHW.new(self) if axb? && (-999..999).cover?(registers[1114])
      @humidistat = Humidistat.new(self,
                                   @abc_dipswitches[:accessory_relay] == :humidifier,
                                   axb? && @axb_dipswitches[:accessory_relay2] == :dehumidifier)
      @humidistat = nil unless @humidistat.humidifier? || @humidistat.dehumidifier? || awl_communicating?
      @faults = []

      @entering_air_register = awl_axb? ? 740 : 567
      @registers_to_read = [6, 19..20, 25, 30..31, 112, 344, @entering_air_register]
      @registers_to_read << 1104 if axb?
      @registers_to_read.push(741..742) if awl_communicating?
      @registers_to_read << (1110..1111) if performance_monitoring?
      @registers_to_read.push(16, 1150..1153) if energy_monitoring?
      @registers_to_read << 900 if awl_axb?
      zones.each do |z|
        @registers_to_read.concat(z.registers_to_read)
      end
      @components = [aux_heat, compressor, blower, pump, dhw, humidistat].compact
      @components.each do |component|
        @registers_to_read.concat(component.registers_to_read)
      end
      # need dehumidify mode to calculate final current mode
      @registers_to_read.push(362) if compressor.is_a?(Compressor::VSDrive)
    end

    def query_registers(query)
      self.class.query_registers(@modbus_slave, query)
    end

    def refresh
      faults = @modbus_slave.read_multiple_holding_registers(601..699)
      @faults = Aurora.transform_registers(faults).values

      registers = @modbus_slave.holding_registers[*@registers_to_read]
      Aurora.transform_registers(registers)

      outputs = registers[30]

      @entering_air_temperature   = registers[@entering_air_register]
      @leaving_air_temperature    = registers[900] if awl_axb?
      if performance_monitoring?
        @leaving_water_temperature  = registers[1110]
        @entering_water_temperature = registers[1111]
      end
      @outdoor_temperature        = registers[742]
      @air_coil_temperature       = registers[20]
      @locked_out                 = registers[25].anybits?(0x8000)
      @current_fault              = registers[25] & 0x7fff
      @derated                    = (41..46).cover?(@current_fault)
      @safe_mode                  = [47, 48, 49, 72, 74].include?(@current_fault)
      @low_pressure_switch        = registers[31][:lps]
      @high_pressure_switch       = registers[31][:hps]
      @emergency_shutdown         = !!registers[31][:emergency_shutdown]
      @load_shed                  = !!registers[31][:load_shed]
      @line_voltage               = registers[16] if energy_monitoring?
      @line_voltage_setting       = registers[112]
      @watts                      = registers[1153]

      @current_mode = if outputs.include?(:lockout)
                        :lockout
                      elsif registers[362]
                        :dehumidify
                      elsif outputs.include?(:cc2) || outputs.include?(:cc)
                        if outputs.include?(:rv)
                          :cooling
                        elsif outputs.include?(:eh2) || outputs.include?(:eh1)
                          :heating_with_aux
                        else
                          :heating
                        end
                      elsif outputs.include?(:eh2) || outputs.include?(:eh1)
                        :emergency_heat
                      elsif outputs.include?(:blower)
                        :blower
                      elsif !registers[6].zero?
                        :waiting
                      else
                        :standby
                      end

      zones.each do |z|
        z.refresh(registers)
      end
      @components.each do |component|
        component.refresh(registers)
      end
    end

    def cooling_airflow_adjustment=(value)
      value = 0x10000 + value if value.negative?
      @modbus_slave.holding_registers[346] = value
    end

    def loop_pressure_trip=(value)
      @modbus_slave.holding_registers[419] = (value * 10).to_i
    end

    def line_voltage_setting=(value)
      raise ArgumentError unless (90..635).cover?(value)

      @modbus_slave.holding_registers[112] = value
    end

    def clear_fault_history
      @modbus_slave.holding_registers[47] = 0x5555
    end

    def manual_operation(mode: :off,
                         compressor_speed: 0,
                         blower_speed: :with_compressor,
                         pump_speed: :with_compressor,
                         aux_heat: false)
      raise ArgumentError, "mode must be :off, :heating, or :cooling" unless %i[off heating cooling].include?(mode)
      raise ArgumentError, "compressor speed must be between 0 and 12" unless (0..12).cover?(compressor_speed)

      unless blower_speed == :with_compressor || (0..12).cover?(blower_speed)
        raise ArgumentError,
              "blower speed must be :with_compressor or between 0 and 12"
      end
      unless pump_speed == :with_compressor || (0..100).cover?(pump_speed)
        raise ArgumentError,
              "pump speed must be :with_compressor or between 0 and 100"
      end

      value = 0
      value = 0x7fff if mode == :off
      value |= 0x100 if mode == :cooling
      value |= (blower_speed == :with_compressor) ? 0xf0 : (blower_speed << 4)
      value |= 0x200 if aux_heat

      @modbus_slave.holding_registers[3002] = value
      @modbus_slave.holding_registers[323] = (pump_speed == :with_compressor) ? 0x7fff : pump_speed
    end

    # I'm not sure if this is correct. 5 Series documentation says
    # that performance monitoring is an optional kit that requires
    # an AXB, but AID Tool Sensor Kit Setup only lets you choose
    # between None, Compressor Monitor, and Energy Monitor. So I'm
    # assuming for now that _any_ AXB has at least performance
    # monitoring.
    def performance_monitoring?
      axb?
    end

    def refrigeration_monitoring?
      @energy_monitor >= 1
    end

    def energy_monitoring?
      @energy_monitor == 2
    end

    # config aurora system
    { thermostat: 800, axb: 806, iz2: 812, aoc: 815, moc: 818, eev2: 824, awl: 827 }.each do |(component, register)|
      class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{component}?
          return @#{component} if instance_variable_defined?(:@#{component})
          @#{component} = @modbus_slave.holding_registers[#{register}] != 3
        end

        def #{component}_version
          return @#{component}_version if instance_variable_defined?(:@#{component}_version)
          @#{component}_version = @modbus_slave.holding_registers[#{register + 1}].to_f / 100
        end

        def add_#{component}
          @modbus_slave.holding_registers[#{register}] = 2
        end

        def remove_#{component}
          @modbus_slave.holding_registers[#{register}] = 3
        end
      RUBY
    end

    # see https://www.waterfurnace.com/literature/symphony/ig2001ew.pdf
    # is there a communicating system compliant with AWL?
    def awl_communicating?
      awl_thermostat? || awl_iz2?
    end

    # is the thermostat AWL compliant?
    def awl_thermostat?
      thermostat? && thermostat_version >= 3.0
    end

    # is the IZ2 AWL compliant?
    def awl_iz2?
      iz2? && iz2_version >= 2.0
    end

    # is the AXB AWL compliant?
    def awl_axb?
      axb? && axb_version >= 2.0
    end

    def inspect
      "#<Aurora::ABCClient #{(instance_variables - [:@modbus_slave]).map do |iv|
                               "#{iv}=#{instance_variable_get(iv).inspect}"
                             end.join(", ")}>"
    end
  end
end
