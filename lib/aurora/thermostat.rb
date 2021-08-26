# frozen_string_literal: true

module Aurora
  class Thermostat
    attr_reader :target_mode,
                :target_fan_mode,
                :cooling_target_temperature,
                :heating_target_temperature

    def initialize(abc)
      @abc = abc
    end

    def refresh(registers)
      @heating_target_temperature = registers[746]
      @cooling_target_temperature = registers[745]
    end

    def target_mode=(value)
      return unless (value = HEATING_MODE.invert[value])

      @abc.modbus_slave.holding_registers[12_602] = value
    end

    def target_fan_mode=(value)
      return unless (value = FAN_MODE.invert[value])

      @abc.modbus_slave.holding_registers[12_621] = value
    end

    def heating_target_temperature=(value)
      return unless value >= 40 && value <= 90

      value = (value * 10).to_i
      @abc.modbus_slave.holding_registers[12_619] = value
    end

    def cooling_target_temperature=(value)
      return unless value >= 54 && value <= 99

      value = (value * 10).to_i
      @abc.modbus_slave.holding_registers[12_620] = value
    end

    def inspect
      "#<Aurora::Thermostat #{(instance_variables - [:@abc]).map do |iv|
                                "#{iv}=#{instance_variable_get(iv).inspect}"
                              end.join(', ')}>"
    end
  end
end
