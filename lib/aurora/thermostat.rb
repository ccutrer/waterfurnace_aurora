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
                :fan_intermittent_off,
                :outdoor_reset,
                :effective_target_temperature

    def registers_to_read
      return [] unless @abc.awl_thermostat?

      registers = [502, 745..746, 12_005..12_006]
      registers << 747 if @abc.water_to_water?
      registers
    end

    def refresh(registers)
      if @abc.awl_thermostat?
        @ambient_temperature = registers[502]
        @heating_target_temperature = registers[745]
        @cooling_target_temperature = registers[746]
        if @abc.water_to_water?
          # the setpoint actually in use, e.g. after outdoor reset adjusts it; 0 when off
          effective = registers[747]
          @effective_target_temperature = effective.zero? ? nil : effective
        end
        config1 = registers[12_005]
        config2 = registers[12_006]
        @target_fan_mode = config1[:fan]
        @fan_intermittent_on = config1[:on_time]
        @fan_intermittent_off = config1[:off_time]
        mode = config2[:mode]
        if @abc.water_to_water?
          # outdoor reset is a variant of heat mode, so report it as heat plus a flag
          @outdoor_reset = mode == :outdoor_reset
          mode = :heat if @outdoor_reset
        elsif mode == :outdoor_reset
          mode = nil # only meaningful on the Hydrostat
        end
        @target_mode = mode
      end

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
      # selecting heat again shouldn't silently turn outdoor reset off
      value = :outdoor_reset if value == :heat && outdoor_reset
      return if value == :outdoor_reset && !@abc.water_to_water?
      return unless (raw_value = HEATING_MODE.invert[value])

      @abc.modbus_slave.holding_registers[12_606] = raw_value
      @outdoor_reset = (value == :outdoor_reset) if @abc.water_to_water?
    end

    # Hydrostat preset: outdoor reset (heating, with the setpoint adjusted by outdoor temperature) or none
    def preset_mode
      outdoor_reset ? :outdoor_reset : :none
    end

    def preset_mode=(value)
      return unless %i[outdoor_reset none].include?(value)
      return if value == :none && !outdoor_reset # nothing to clear

      # like on the Hydrostat, choosing outdoor reset implies heating; clearing it leaves plain heat
      mode = (value == :outdoor_reset) ? :outdoor_reset : :heat
      @abc.modbus_slave.holding_registers[12_606] = HEATING_MODE.invert[mode]
      @outdoor_reset = (mode == :outdoor_reset)
    end

    def target_fan_mode=(value)
      return unless (raw_value = FAN_MODE.invert[value])

      @abc.modbus_slave.holding_registers[12_621] = raw_value
    end

    # water-to-water setpoints are (buffer tank) water temperatures, not room temperatures
    def heating_target_temperature_range
      @abc.water_to_water? ? 80..140 : 40..90
    end

    def cooling_target_temperature_range
      @abc.water_to_water? ? 40..85 : 54..99
    end

    def heating_target_temperature=(value)
      return unless heating_target_temperature_range.cover?(value)

      raw_value = (value * 10).to_i
      @abc.modbus_slave.holding_registers[12_619] = raw_value
    end

    def cooling_target_temperature=(value)
      return unless cooling_target_temperature_range.cover?(value)

      raw_value = (value * 10).to_i
      @abc.modbus_slave.holding_registers[12_620] = raw_value
    end

    def fan_intermittent_on=(value)
      return unless value.between?(0, 25) && (value % 5).zero?

      holding_registers[12_622] = value
    end

    def fan_intermittent_off=(value)
      return unless value.between?(0, 40) && (value % 5).zero?

      holding_registers[12_623] = value
    end
  end
end
