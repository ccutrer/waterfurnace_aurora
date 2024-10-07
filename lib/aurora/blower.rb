# frozen_string_literal: true

require "aurora/component"

module Aurora
  module Blower
    class PSC < Component
      attr_reader :type, :watts, :running
      alias_method :running?, :running

      def initialize(abc, type)
        super(abc)
        @type = type
      end

      def registers_to_read
        if abc.energy_monitoring?
          [1148..1149]
        else
          []
        end
      end

      def refresh(registers)
        @watts = registers[1148] if abc.energy_monitoring?
        @running = registers[30].include?(:blower)
      end
    end

    class FiveSpeed < PSC
      attr_reader :speed

      def speed_range
        0..4
      end

      def refresh(registers)
        outputs = registers[30]
        @speed = if outputs.include?(:eh1) || outputs.include?(:eh2)
                   4
                 elsif outputs.include?(:cc2)
                   3
                 elsif outputs.include?(:cc)
                   2
                 elsif outputs.include?(:blower)
                   1
                 else
                   0
                 end
      end
    end

    class ECM < PSC
      attr_reader :speed,
                  :blower_only_speed,
                  :low_compressor_speed,
                  :high_compressor_speed,
                  :aux_heat_speed,
                  :iz2_desired_speed

      def speed_range
        0..12
      end

      def registers_to_read
        result = super + [340..342, 344, 347]
        result << 565 if abc.iz2?
        result
      end

      def refresh(registers)
        super

        @speed                  = registers[344]
        @blower_only_speed      = registers[340]
        @low_compressor_speed   = registers[341]
        @high_compressor_speed  = registers[342]
        @aux_heat_speed         = registers[347]
        @iz2_desired_speed      = registers[565] if abc.iz2?
      end

      { blower_only: 340,
        low_compressor: 341,
        high_compressor: 342,
        aux_heat: 347 }.each do |(setting, register)|
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{setting}_speed=(value)
            raise ArgumentError unless (1..12).include?(value)

            holding_registers[#{register}] = value
          end
        RUBY
      end
    end
  end
end
