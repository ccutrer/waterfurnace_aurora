module Aurora
  class ABCClient
    attr_reader :modbus_slave,
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
      :fp2

    def initialize(modbus_slave)
      @modbus_slave = modbus_slave
      @modbus_slave.read_retry_timeout = 15
      @modbus_slave.read_retries = 2
      iz2_zone_count = @modbus_slave.holding_registers[483]
      @iz2_zones = (0...iz2_zone_count).map { |i| IZ2Zone.new(self, i + 1) }
    end

    def refresh
      registers_to_read = [19..20, 30, 344, 740..741, 900, 1110..1111, 1114, 1117, 3027, 31003]
      # IZ2 zones
      iz2_zones.each_with_index do |_z, i|
        base1 = 21203 + i * 9
        base2 = 31007 + i * 3
        base3 = 31200 + i * 3
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
      @outdoor_temperature        = registers[31003]
      @fp1                        = registers[19]
      @fp2                        = registers[20]
      @locked_out                 = registers[1117]

      outputs = registers[30]
      if outputs.include?(:lockout)
        @current_mode = :lockout
      elsif outputs.include?(:cc2)
        @current_mode = outputs.include?(:rv) ? :c2 : :h2
      elsif outputs.include?(:cc)
        @current_mode = outputs.include?(:rv) ? :c1 : :h1
      elsif outputs.include?(:eh2)
        @current_mode = :eh2
      elsif outputs.include?(:eh1)
        @current_mode = :eh1
      elsif outputs.include?(:blower)
        @current_mode = :blower
      else
        @current_mode = :standby
      end

      iz2_zones.each do |z|
        z.refresh(registers)
      end
    end

    def inspect
      "#<Aurora::ABCClient #{(instance_variables - [:@modbus_slave]).map { |iv| "#{iv}=#{instance_variable_get(iv).inspect}" }.join(', ')}>"
    end
  end
end
