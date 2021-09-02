# frozen_string_literal: true

require "aurora/component"

module Aurora
  class Humidifier < Component
    attr_reader :running
    alias running? running

    def refresh(registers)
      outputs = registers[30]
      @running = outputs.include?(:accessory)
    end
  end
end
