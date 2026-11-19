# frozen_string_literal: true

require "aurora/component"

module Aurora
  class Humidistat < Component
    attr_reader :humidifier_running,
                :humidifier_mode,
                :humidification_target,
                :dehumidifier_mode,
                :dehumidification_target,
                :humidity_offset,
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
        result.concat(abc.iz2? ? [31_109..31_110] : [12_309..12_310])
      end
      result
    end

    def refresh(registers)
      @relative_humidity = registers[741]

      outputs = registers[30]
      @humidifier_running = humidifier? && outputs.include?(:accessory)

      if abc.axb?
        outputs = registers[1104]
        @dehumidifier_running = dehumidifier? && outputs.include?(:accessory2)
      end

      return unless abc.awl_communicating?

      base = abc.iz2? ? 31_109 : 12_309
      # Read the settings back from the read register; on IZ2 systems the write register
      # (21114) reads as 0 until something writes to it.
      settings = registers[base]
      @humidifier_settings = settings && raw_humidifier_settings(settings)
      @humidifier_mode = settings&.include?(:auto_humidification) ? :auto : :manual
      @dehumidifier_mode = settings&.include?(:auto_dehumidification) ? :auto : :manual
      # The installer Humidity Offset lives in the low 5 bits, as a signed value.
      # Only verified on IZ2 (MasterStat) systems.
      @humidity_offset = (@humidifier_settings && abc.iz2?) ? signed_offset(@humidifier_settings) : nil

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

      # Start with the current value of the register, so that everything else
      # stuffed in there (such as the humidity offset) is preserved
      raw_value = current_humidifier_settings & ~(AUTO_HUMIDIFICATION | AUTO_DEHUMIDIFICATION)
      raw_value |= AUTO_HUMIDIFICATION if humidifier_mode == :auto
      raw_value |= AUTO_DEHUMIDIFICATION if dehumidifier_mode == :auto
      holding_registers[abc.iz2? ? 21_114 : 12_309] = raw_value
    end

    def humidity_offset=(value)
      raise ArgumentError unless abc.iz2?
      raise ArgumentError unless (-10..10).cover?(value)

      raw_value = (current_humidifier_settings & ~OFFSET_MASK) | (value & OFFSET_MASK)
      holding_registers[21_114] = raw_value
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

    private

    # must match Aurora::HUMIDIFIER_SETTINGS (registers.rb is loaded after this file)
    AUTO_HUMIDIFICATION = 0x8000
    AUTO_DEHUMIDIFICATION = 0x4000
    OFFSET_MASK = 0x1f
    private_constant :AUTO_HUMIDIFICATION, :AUTO_DEHUMIDIFICATION, :OFFSET_MASK

    # rebuild the raw register value from Aurora.from_bitmask's output
    def raw_humidifier_settings(settings)
      settings.sum do |flag|
        flag.is_a?(Symbol) ? Aurora::HUMIDIFIER_SETTINGS.key(flag) : flag[2..].to_i(16)
      end
    end

    def signed_offset(raw_value)
      offset = raw_value & OFFSET_MASK
      offset.anybits?(0x10) ? offset - 0x20 : offset
    end

    # Read the register fresh rather than trusting the last refresh, so that
    # back-to-back writes don't clobber each other
    def current_humidifier_settings
      holding_registers[abc.iz2? ? 31_109 : 12_309]
    end
  end
end
