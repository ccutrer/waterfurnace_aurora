# frozen_string_literal: true

module Aurora
  class ABCClient
    attr_reader :modbus_slave,
                :thermostat,
                :iz2_zones,
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
                :compressor_watts,
                :blower_watts,
                :aux_heat_watts,
                :loop_pump_watts,
                :total_watts

    def initialize(modbus_slave)
      @modbus_slave = modbus_slave
      @modbus_slave.read_retry_timeout = 15
      @modbus_slave.read_retries = 2
      iz2_zone_count = @modbus_slave.holding_registers[483]
      # TODO: better detect IZ2/Non-IZ2
      if iz2_zone_count > 1
        @iz2_zones = (0...iz2_zone_count).map { |i| IZ2Zone.new(self, i + 1) }
      else
        @iz2_zones = []
        @thermostat = Thermostat.new(self)
      end
    end

    def refresh
      registers_to_read = [19..20, 30, 344, 740..741, 900, 1110..1111, 1114, 1117, 1147..1153, 1165, 3027, 31_003]
      registers_to_read << 745..746 if thermostat
      iz2_zones.each_with_index do |_z, i|
        base1 = 21_203 + i * 9
        base2 = 31_007 + i * 3
        base3 = 31_200 + i * 3
        registers_to_read << (base1..(base1 + 1))
        registers_to_read << (base2..(base2 + 2))
        registers_to_read << base3
      end

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
      @locked_out                 = registers[1117]
      @compressor_watts           = registers[1147]
      @blower_watts               = registers[1149]
      @aux_heat_watts             = registers[1151]
      @loop_pump_watts            = registers[1165]
      @total_watts                = registers[1153]

      outputs = registers[30]
      @current_mode = if outputs.include?(:lockout)
                        :lockout
                      elsif outputs.include?(:cc2)
                        outputs.include?(:rv) ? :c2 : :h2
                      elsif outputs.include?(:cc)
                        outputs.include?(:rv) ? :c1 : :h1
                      elsif outputs.include?(:eh2)
                        :eh2
                      elsif outputs.include?(:eh1)
                        :eh1
                      elsif outputs.include?(:blower)
                        :blower
                      else
                        :standby
                      end

      thermostat&.refresh(registers)
      iz2_zones.each do |z|
        z.refresh(registers)
      end
    end

    def inspect
      "#<Aurora::ABCClient #{(instance_variables - [:@modbus_slave]).map do |iv|
                               "#{iv}=#{instance_variable_get(iv).inspect}"
                             end.join(', ')}>"
    end
  end
end
