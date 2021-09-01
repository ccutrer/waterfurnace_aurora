# frozen_string_literal: true

module Aurora
  class Component
    def initialize(abc)
      @abc = abc
    end

    private

    attr_reader :abc

    def holding_registers
      abc.modbus_slave.holding_registers
    end
  end
end
