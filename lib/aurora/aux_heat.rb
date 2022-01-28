# frozen_string_literal: true

require "aurora/component"

module Aurora
  class AuxHeat < Component
    attr_reader :stage, :watts

    def refresh(registers)
      outputs = registers[30]
      @stage = if outputs.include?(:eh2)
                 2
               elsif outputs.include?(:eh1)
                 1
               else
                 0
               end
      @watts = registers[1151] if abc.energy_monitoring?
    end
  end
end
