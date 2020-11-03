module Aurora
  class IZ2Zone
    attr_reader :zone_number,
      :target_mode,
      :current_mode,
      :target_fan_mode,
      :current_fan_mode,
      :fan_intermittent_on,
      :fan_intermittent_off,
      :priority,
      :size, :normalized_size,
      :ambient_temperature,
      :cooling_target_temperature,
      :heating_target_temperature

    def initialize(abc, zone_number)
      @abc = abc
      @zone_number = zone_number
    end

    def refresh(registers)
      @ambient_temperature = registers[31007 + (zone_number - 1) * 3]

      config1 = registers[31008 + (zone_number - 1) * 3]
      config2 = registers[31009 + (zone_number - 1) * 3]
      config3 = registers[31200 + (zone_number - 1) * 3]

      @target_fan_mode = config1[:fan]
      @fan_intermittent_on = config1[:on_time]
      @fan_intermittent_off = config1[:off_time]
      @cooling_target_temperature = config1[:cooling_target_temperature]
      @heating_target_temperature = config2[:heating_target_temperature]
      @target_mode = config2[:mode]
      @current_mode = config2[:call]
      @current_fan_mode = config2[:damper] == :open

      @priority = config3[:zone_priority]
      @size = config3[:zone_size]
      @normalized_size = config3[:normalized_size]
    end

    def target_mode=(value)
      value = Aurora::HEATING_MODE.invert[value]
      return unless value
      @abc.modbus_slave.holding_registers[21202 + (zone_number - 1) * 9] = value
      @target_mode = Aurora::HEATING_MODE[@abc.modbus_slave.holding_registers[21202 + (zone_number - 1) * 9]]
    end

    def target_fan_mode=(value)
      value = Aurora::FAN_MODE.invert[value]
      return unless value
      @abc.modbus_slave.holding_registers[21205 + (zone_number - 1) * 9] = value
      registers = @abc.modbus_slave.read_multiple_holding_registers(31008 + (zone_number - 1) * 3)
      Aurora.transform_registers(registers)
      @target_fan_mode = registers.first.last[:fan]
    end

    def fan_intermittent_on=(value)
      return unless value >= 0 && value <= 25 && value % 5 == 0
      @abc.modbus_slave.holding_registers[21206 + (zone_number - 1) * 9] = value
      registers = @abc.modbus_slave.read_multiple_holding_registers(31008 + (zone_number - 1) * 3)
      Aurora.transform_registers(registers)
      @fan_intermittent_on = registers.first.last[:on_time]
    end

    def fan_intermittent_off=(value)
      return unless value >= 0 && value <= 40 && value % 5 == 0
      @abc.modbus_slave.holding_registers[21207 + (zone_number - 1) * 9] = value
      registers = @abc.modbus_slave.read_multiple_holding_registers(31008 + (zone_number - 1) * 3)
      Aurora.transform_registers(registers)
      @fan_intermittent_on = registers.first.last[:off_time]
    end

    def heating_target_temperature=(value)
      return unless value >= 40 && value <= 90
      value = (value * 10).to_i
      @abc.modbus_slave.holding_registers[21203 + (zone_number - 1) * 9] = value

      base = 31008 + (zone_number - 1) * 3
      registers = @abc.modbus_slave.read_multiple_holding_registers(base..(base + 1))
      Aurora.transform_registers(registers)
      registers[base + 1][:heating_target_temperature]
    end

    def cooling_target_temperature=(value)
      return unless value >= 54 && value <= 99
      value = (value * 10).to_i
      @abc.modbus_slave.holding_registers[21204 + (zone_number - 1) * 9] = value

      registers = @abc.modbus_slave.read_multiple_holding_registers(31008 + (zone_number - 1) * 3)
      Aurora.transform_registers(registers)
      registers.first.last[:cooling_target_temperature]
    end

    def inspect
      "#<Aurora::IZ2Zone #{(instance_variables - [:@abc]).map { |iv| "#{iv}=#{instance_variable_get(iv).inspect}" }.join(', ')}>"
    end
  end
end
