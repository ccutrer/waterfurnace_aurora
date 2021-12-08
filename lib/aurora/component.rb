# frozen_string_literal: true

module Aurora
  class Component
    def initialize(abc)
      @abc = abc
    end

    def inspect
      "#<Aurora::#{self.class.name} #{(instance_variables - [:@abc]).map do |iv|
                                        "#{iv}=#{instance_variable_get(iv).inspect}"
                                      end.join(", ")}>"
    end

    private

    attr_reader :abc

    def holding_registers
      abc.modbus_slave.holding_registers
    end
  end
end
