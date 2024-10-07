# frozen_string_literal: true

require "aurora/component"

module Aurora
  class Humidistat < Component
    attr_reader :humidifier_running,
                :humidifier_mode,
                :humidification_target,
                :dehumidifier_mode,
                :dehumidification_target,
                :relative_humidity
    alias_method :humidifier_running?, :humidifier_running

    def initialize(abc, has_humidifier, has_dehumidifier)
      super(abc)
      @humidifier = has_humidifier
      @dehumidifier = has_dehumidifier
    end

    def humidifier?
      @humidifier
    end

    def dehumidifier?
      @dehumidifier
    end

    def dehumidifier_running
      dehumidifier? ? @dehumidifier_running : abc.current_mode == :dehumidify
    end
    alias_method :dehumidifier_running?, :dehumidifier_running

    def registers_to_read
      return [] unless @abc.awl_communicating?

      result = [741]
      if humidifier? || dehumidifier? || abc.compressor.is_a?(Compressor::VSDrive)
        result.concat(abc.iz2? ? [21_114, 31_109..31_110] : [12_309..12_310])
      end
      result
    end

    def refresh(registers)
      @relative_humidity = registers[741]

      outputs = registers[30]
      @humidifier_running = humidifier? && outputs.include?(:accessory)

      if abc.axb?
        outputs = registers[1104]
        @dehumidifer_running = dehumidifier? && outputs.include?(:accessory2)
      end

      return unless abc.awl_communicating?

      base = abc.iz2? ? 31_109 : 12_309
      humidifier_settings_register = abc.iz2? ? 21_114 : 12_309
      @humidifier_settings = registers[humidifier_settings_register]&.last&.[](2..-1)&.to_i(16)
      @humidifier_mode = registers[humidifier_settings_register]&.include?(:auto_humidification) ? :auto : :manual
      @dehumidifier_mode = registers[humidifier_settings_register]&.include?(:auto_dehumidification) ? :auto : :manual

      @humidification_target = registers[base + 1]&.[](:humidification_target)
      @dehumidification_target = registers[base + 1]&.[](:dehumidification_target)
    end

    def humidifier_mode=(mode)
      set_humidistat_mode(mode, dehumidifier_mode)
    end

    def dehumidifier_mode=(mode)
      set_humidistat_mode(humidifier_mode, mode)
    end

    def set_humidistat_mode(humidifier_mode, dehumidifier_mode)
      allowed = %i[auto manual]
      raise ArgumentError unless allowed.include?(humidifier_mode) && allowed.include?(dehumidifier_mode)

      # start with the prior value of the register, since I'm not sure what
      # else is stuffed in there
      raw_value = @humidifier_settings
      raw_value |= 0x4000 if humidifier_mode == :auto
      raw_value |= 0x8000 if dehumidifier_mode == :auto
      holding_registers[abc.iz2? ? 21_114 : 12_309] = raw_value
    end

    def humidification_target=(value)
      set_humidistat_targets(value, dehumidification_target)
    end

    def dehumidification_target=(value)
      set_humidistat_targets(humidification_target, value)
    end

    def set_humidistat_targets(humidification_target, dehumidification_target)
      raise ArgumentError unless (15..50).cover?(humidification_target)
      raise ArgumentError unless (35..65).cover?(dehumidification_target)

      holding_registers[abc.iz2? ? 21_115 : 12_310] = (humidification_target << 8) + dehumidification_target
    end
  end
end
