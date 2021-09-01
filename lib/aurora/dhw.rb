# frozen_string_literal: true

require "aurora/component"

module Aurora
  class DHW < Component
    attr_reader :enabled, :set_point, :water_temperature

    def registers_to_read
      [400..401, 1114]
    end

    def refresh(registers)
      @enabled = registers[400]
      @set_point = registers[401]
      @water_temperature = registers[1114]
    end

    def enabled=(value)
      holding_registers[400] = value ? 1 : 0
    end

    def set_point=(value) # rubocop:disable Naming/AccessorMethodName
      raise ArgumentError unless (100..140).include?(value)

      raw_value = (value * 10).to_i
      holding_registers[401] = raw_value
      @set_point = value
    end
  end
end
