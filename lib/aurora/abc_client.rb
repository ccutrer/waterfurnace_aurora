# frozen_string_literal: true

module Aurora
  class ABCClient
    attr_reader :modbus_slave,
                :serial_number,
                :zones,
                :faults,
                :current_mode,
                :fan_speed,
                :entering_air_temperature,
                :relative_humidity,
                :leaving_air_temperature,
                :leaving_water_temperature,
                :entering_water_temperature,
                :dhw_water_temperature,
                :waterflow,
                :compressor_speed,
                :outdoor_temperature,
                :fp1,
                :fp2,
                :blower_only_ecm_speed,
                :aux_heat_ecm_speed,
                :compressor_watts,
                :blower_watts,
                :aux_heat_watts,
                :loop_pump_watts,
                :total_watts

    def initialize(modbus_slave)
      @modbus_slave = modbus_slave
      @modbus_slave.read_retry_timeout = 15
      @modbus_slave.read_retries = 2
      registers_array = @modbus_slave.holding_registers[105...110]
      registers = registers_array.each_with_index.map { |r, i| [i + 105, r] }.to_h
      @serial_number = Aurora.transform_registers(registers)[105]

      @zones = if iz2?
                 iz2_zone_count = @modbus_slave.holding_registers[483]
                 (0...iz2_zone_count).map { |i| IZ2Zone.new(self, i + 1) }
               else
                 [Thermostat.new(self)]
               end
      @faults = []
    end

    def query_registers(query)
      ranges = query.split(",").map do |addr|
        case addr
        when "known"
          Aurora::REGISTER_NAMES.keys
        when "valid"
          break Aurora::REGISTER_RANGES
        when /^(\d+)(?:\.\.|-)(\d+)$/
          $1.to_i..$2.to_i
        else
          addr.to_i
        end
      end
      queries = Aurora.normalize_ranges(ranges)
      registers = {}
      queries.each do |subquery|
        registers.merge!(@modbus_slave.read_multiple_holding_registers(*subquery))
      end
      registers
    end

    def refresh
      registers_to_read = [6, 19..20, 25, 30, 340, 344, 347, 362, 740..741, 900, 1110..1111, 1114, 1147..1153, 1165,
                           3027, 31_003]
      if zones.first.is_a?(IZ2Zone)
        zones.each_with_index do |_z, i|
          base1 = 21_203 + i * 9
          base2 = 31_007 + i * 3
          base3 = 31_200 + i * 3
          registers_to_read << (base1..(base1 + 1))
          registers_to_read << (base2..(base2 + 2))
          registers_to_read << base3
        end
      else
        registers_to_read << 502
        registers_to_read << (745..746)
      end

      @faults = @modbus_slave.holding_registers[601..699]

      registers = @modbus_slave.holding_registers[*registers_to_read]
      Aurora.transform_registers(registers)

      @fan_speed                  = registers[344]
      @entering_air_temperature   = registers[740]
      @relative_humidity          = registers[741]
      @leaving_air_temperature    = registers[900]
      @leaving_water_temperature  = registers[1110]
      @entering_water_temperature = registers[1111]
      @dhw_water_temperature      = registers[1114]
      @waterflow                  = registers[1117]
      @compressor_speed           = registers[3027]
      @outdoor_temperature        = registers[31_003]
      @fp1                        = registers[19]
      @fp2                        = registers[20]
      @locked_out                 = registers[25] & 0x8000
      @error                      = registers[25] & 0x7fff
      @derated                    = (41..46).include?(@error)
      @safe_mode                  = [47, 48, 49, 72, 74].include?(@error)
      @blower_only_ecm_speed      = registers[340]
      @aux_heat_ecm_speed         = registers[347]
      @compressor_watts           = registers[1147]
      @blower_watts               = registers[1149]
      @aux_heat_watts             = registers[1151]
      @loop_pump_watts            = registers[1165]
      @total_watts                = registers[1153]

      outputs = registers[30]
      @current_mode = if outputs.include?(:lockout)
                        :lockout
                      elsif registers[362]
                        :dehumidify
                      elsif outputs.include?(:cc2)
                        outputs.include?(:rv) ? :c2 : :h2
                      elsif outputs.include?(:cc)
                        outputs.include?(:rv) ? :c1 : :h1
                      elsif outputs.include?(:eh2)
                        outputs.include?(:rv) ? :eh2 : :emergency
                      elsif outputs.include?(:eh1)
                        outputs.include?(:rv) ? :eh1 : :emergency
                      elsif outputs.include?(:blower)
                        :blower
                      elsif registers[6]
                        :waiting
                      else
                        :standby
                      end

      zones.each do |z|
        z.refresh(registers)
      end
    end

    def blower_only_ecm_speed=(value)
      return unless (1..12).include?(value)

      @modbus_slave.holding_registers[340] = value
    end

    def aux_heat_ecm_speed=(value)
      return unless (1..12).include?(value)

      @modbus_slave.holding_registers[347] = value
    end

    def cooling_airflow_adjustment=(value)
      value = 0x10000 + value if value.negative?
      @modbus_slave.holding_registers[346] = value
    end

    def dhw_enabled=(value)
      @modbus_slave.holding_registers[400] = value ? 1 : 0
    end

    def dhw_setpoint=(value)
      @modbus_slave.holding_registers[401] = value
    end

    def loop_pressure_trip=(value)
      @modbus_slave.holding_registers[419] = (value * 10).to_i
    end

    def vs_pump_control=(value)
      raise ArgumentError unless (value = VS_PUMP_CONTROL.invert[value])

      @modbus_slave.holding_registers[323] = value
    end

    def vs_pump_min=(value)
      @modbus_slave.holding_registers[321] = value
    end

    def vs_pump_max=(value)
      @modbus_slave.holding_registers[322] = value
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
      raise ArgumentError, "compressor speed must be between 0 and 12" unless (0..12).include?(compressor_speed)

      unless blower_speed == :with_compressor || (0..12).include?(blower_speed)
        raise ArgumentError,
              "blower speed must be :with_compressor or between 0 and 12"
      end
      unless pump_speed == :with_compressor || (0..100).include?(pump_speed)
        raise ArgumentError,
              "pump speed must be :with_compressor or between 0 and 100"
      end

      value = 0
      value = 0x7fff if mode == :off
      value |= 0x100 if mode == :cooling
      value |= blower_speed == :with_compressor ? 0xf0 : (blower_speed << 4)
      value |= 0x200 if aux_heat

      @modbus_slave.holding_registers[3002] = value
      @modbus_slave.holding_registers[323] = pump_speed == :with_compressor ? 0x7fff : pump_speed
    end

    # config aurora system
    { thermostat: 800, axb: 806, iz2: 812, aoc: 815, moc: 818, eev2: 824 }.each do |(component, register)|
      class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{component}?
          @modbus_slave.holding_registers[#{register}] != 3
        end

        def add_#{component}
          @modbus_slave.holding_registers[#{register}] = 2
        end

        def remove_#{component}
          @modbus_slave.holding_registers[#{register}] = 3
        end
      RUBY
    end

    def inspect
      "#<Aurora::ABCClient #{(instance_variables - [:@modbus_slave]).map do |iv|
                               "#{iv}=#{instance_variable_get(iv).inspect}"
                             end.join(', ')}>"
    end
  end
end
