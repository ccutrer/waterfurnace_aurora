# frozen_string_literal: true

require "aurora/component"

module Aurora
  class Thermostat < Component
    attr_reader :target_mode,
                :target_fan_mode,
                :ambient_temperature,
                :cooling_target_temperature,
                :heating_target_temperature

    def refresh(registers)
      @ambient_temperature = registers[502]
      @heating_target_temperature = registers[746]
      @cooling_target_temperature = registers[745]
    end

    def target_mode=(value)
      return unless (raw_value = HEATING_MODE.invert[value])

      @abc.modbus_slave.holding_registers[12_606] = raw_value
      @target_mode = value
    end

    def target_fan_mode=(value)
      return unless (raw_value = FAN_MODE.invert[value])

      @abc.modbus_slave.holding_registers[12_621] = raw_value
      @target_fan_mode = value
    end

    def heating_target_temperature=(value)
      return unless value >= 40 && value <= 90

      raw_value = (value * 10).to_i
      @abc.modbus_slave.holding_registers[12_619] = raw_value
      @heating_target_temperature = value
    end

    def cooling_target_temperature=(value)
      return unless value >= 54 && value <= 99

      raw_value = (value * 10).to_i
      @abc.modbus_slave.holding_registers[12_620] = raw_value
      @cooling_target_temperature = value
    end

    def inspect
      "#<Aurora::#{self.class.name} #{(instance_variables - [:@abc]).map do |iv|
                                        "#{iv}=#{instance_variable_get(iv).inspect}"
                                      end.join(', ')}>"
    end
  end
end
