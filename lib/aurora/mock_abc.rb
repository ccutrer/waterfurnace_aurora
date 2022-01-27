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
          missing_register(register.first) unless @registers.key?(register.first)
          @registers[register.first]
        when Range
          registers = register.first.to_a
          registers.each do |i|
            missing_register(i) unless @registers.key?(i)
          end
          @registers.values_at(*registers)
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
          unless @registers.key?(i)
            missing_register(i)
            next
          end

          result[i] = @registers[i]
        end
      end
      result
    end

    def write_holding_register(addr, value)
      @registers[addr] = value
    end
    alias_method :[]=, :write_holding_register

    private

    def missing_register(idx)
      logger.warn("missing register #{idx}")
    end
  end
end
