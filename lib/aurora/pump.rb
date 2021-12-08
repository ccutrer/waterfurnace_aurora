# frozen_string_literal: true

require "aurora/component"

module Aurora
  module Pump
    class GenericPump < Component
      attr_reader :type, :watts, :waterflow, :running
      alias_method :running?, :running

      def initialize(abc, type)
        super(abc)
        @type = type
      end

      def registers_to_read
        result = [1117]
        result.concat([1164..1165]) if abc.energy_monitoring?
        result
      end

      def refresh(registers)
        @waterflow = registers[1117]
        @watts = registers[1164] if abc.energy_monitoring?
        @running = registers[1104].include?(:loop_pump)
      end
    end

    class VSPump < GenericPump
      attr_reader :speed, :minimum_speed, :maximum_speed, :manual_control
      alias_method :manual_control?, :manual_control

      def registers_to_read
        super + [321..325]
      end

      def refresh(registers)
        super
        @minimum_speed = registers[321]
        @maximum_speed = registers[322]
        @manual_control = registers[323] != :off
        @speed = registers[325]
      end

      def manual_control=(value)
        holding_registers[323] = value ? speed : 0x7fff
      end

      { speed: 323,
        minimum_speed: 321,
        maximum_speed: 322 }.each do |(setting, register)|
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{setting}=(value)
            raise ArgumentError unless (1..100).include?(value)

            holding_registers[#{register}] = value
          end
        RUBY
      end
    end
  end
end
