# frozen_string_literal: true

require "aurora/component"

module Aurora
  module Compressor
    class GenericCompressor < Component
      attr_reader :speed, :watts

      def initialize(abc, stages)
        super(abc)
        @stages = stages
      end

      def type
        "#{@stages == 2 ? 'Dual' : 'Single'} Stage Compressor"
      end

      def speed_range
        0..@stages
      end

      def registers_to_read
        if abc.energy_monitoring?
          [1146..1147]
        else
          []
        end
      end

      def refresh(registers)
        outputs = registers[30]
        @speed = if outputs.include?(:cc2)
                   2
                 elsif outputs.include?(:cc)
                   1
                 else
                   0
                 end
        @watts = registers[1146] if abc.energy_monitoring?
      end
    end

    class VSDrive < GenericCompressor
      attr_reader :ambient_temperature, :iz2_desired_speed

      def initialize(abc)
        super(abc, 12)
      end

      def type
        "Variable Speed Drive"
      end

      def registers_to_read
        result = super + [209, 3001, 3326]
        result << 564 if abc.iz2?
        result
      end

      def refresh(registers)
        super

        @speed = registers[3001]
        @ambient_temperature = registers[3326]
        @iz2_desired_speed = registers[564] if abc.iz2?
      end
    end
  end
end
