# frozen_string_literal: true

module Aurora
  class MockABC
    attr_accessor :logger

    def initialize(registers)
      @registers = registers
    end

    def read_retry_timeout=(_); end

    def read_retries=(_); end

    def holding_registers
      self
    end

    def [](*register)
      if register.length == 1
        case register.first
        when Integer
          @registers[register.first]
        when Range
          @registers.values_at(*register.first.to_a)
        else
          raise ArgumentError, "Not implemented yet #{register.inspect}"
        end
      else
        read_multiple_holding_registers(*register)
      end
    end

    def read_multiple_holding_registers(*queries)
      result = {}
      queries.each do |query|
        Array(query).each do |i|
          result[i] = @registers[i]
        end
      end
      result
    end

    def write_holding_register(addr, value)
      @registers[addr] = value
    end
    alias []= write_holding_register
  end
end
