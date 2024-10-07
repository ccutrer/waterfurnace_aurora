# frozen_string_literal: true

require "aurora/component"

module Aurora
  class DHW < Component
    attr_reader :enabled, :running, :set_point, :water_temperature
    alias_method :running?, :running

    def registers_to_read
      [400..401, 1114]
    end

    def refresh(registers)
      @enabled = registers[400]
      @running = registers[1104].include?(:dhw)
      @set_point = registers[401]
      @water_temperature = registers[1114]
    end

    def enabled=(value)
      holding_registers[400] = value ? 1 : 0
    end

    def set_point=(value)
      raise ArgumentError unless (100..140).cover?(value)

      raw_value = (value * 10).to_i
      holding_registers[401] = raw_value
    end
  end
end
