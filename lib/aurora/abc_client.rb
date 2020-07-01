module Aurora
  class ABCClient
    attr_reader :iz2_zones,
      :outdoor_temperature,
      :fan_speed,
      :compressor_speed

    def initialize(modbus_slave)
      @slave = modbus_slave
      iz2_zone_count = @slave.holding_registers[483]
      @iz2_zones = (0...iz2_zone_count).map { |i| IZ2Zone.new(self, i + 1) }
    end

    def refresh
      registers_to_read = [31003, 344, 3027]
      # IZ2 zones
      iz2_zones.each_with_index do |_z, i|
        base1 = 21203 + i * 9
        base2 = 31007 + i * 3
        base3 = 31200 + i * 3
        registers_to_read << (base1..(base1 + 1))
        registers_to_read << (base2..(base2 + 2))
        registers_to_read << base3
      end

      registers = @slave.holding_registers[*registers_to_read]
      Aurora.transform_registers(registers)
      @outdoor_temperature = registers[31003]
      @fan_speed           = registers[344]
      @compressor_speed    = registers[3027]

      iz2_zones.each do |z|
        z.refresh(registers)
      end
    end

    def inspect
      "#<Aurora::ABCClient #{(instance_variables - [:@slave]).map { |iv| "#{iv}=#{instance_variable_get(iv).inspect}" }.join(', ')}>"
    end
  end
end
