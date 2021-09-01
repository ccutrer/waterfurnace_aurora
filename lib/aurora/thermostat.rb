# frozen_string_literal: true

require "aurora/component"

module Aurora
  class Thermostat < Component
    attr_reader :target_mode,
                :current_mode,
                :target_fan_mode,
                :current_fan_mode,
                :ambient_temperature,
                :cooling_target_temperature,
                :heating_target_temperature,
                :fan_intermittent_on,
                :fan_intermittent_off

    def registers_to_read
      [31, 502, 745..746, 12_005..12_006]
    end

    def refresh(registers)
      @ambient_temperature = registers[502]
      @heating_target_temperature = registers[745]
      @cooling_target_temperature = registers[746]
      config1 = registers[12_005]
      config2 = registers[12_006]
      @target_fan_mode = config1[:fan]
      @fan_intermittent_on = config1[:on_time]
      @fan_intermittent_off = config1[:off_time]
      @target_mode = config2[:mode]

      inputs = registers[31]
      @current_fan_mode = inputs.include?(:g)
      @current_mode = if inputs[:y2]
                        inputs[:o] ? :c2 : :h2
                      elsif inputs[:y1]
                        inputs[:o] ? :c1 : :h1
                      else
                        :standby
                      end
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

    def fan_intermittent_on=(value)
      return unless value >= 0 && value <= 25 && (value % 5).zero?

      holding_registers[12_622] = value
      @fan_intermittent_on = value
    end

    def fan_intermittent_off=(value)
      return unless value >= 0 && value <= 40 && (value % 5).zero?

      holding_registers[12_623] = value
      @fan_intermittent_off = value
    end
  end
end
