# frozen_string_literal: true

require "aurora/component"

module Aurora
  module Compressor
    class GenericCompressor < Component
      attr_reader :speed,
                  :watts,
                  :cooling_liquid_line_temperature,
                  :heating_liquid_line_temperature,
                  :saturated_condensor_discharge_temperature,
                  :heat_of_extraction,
                  :heat_of_rejection

      def initialize(abc, stages)
        super(abc)
        @stages = stages
      end

      def type
        "#{@stages == 2 ? "Dual" : "Single"} Stage Compressor"
      end

      def speed_range
        0..@stages
      end

      def registers_to_read
        result = [19]
        result.concat([1109, 1134, 1146..1147, 1154..1157]) if abc.energy_monitoring?
        result
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
        @cooling_liquid_line_temperature = registers[19]

        return unless abc.energy_monitoring?

        @heating_liquid_line_temperature = registers[1109]
        @saturated_condensor_discharge_temperature = registers[1134]
        @watts = registers[1146]
        @heat_of_extraction = registers[1154]
        @heat_of_rejection = registers[1156]
      end
    end

    class VSDrive < GenericCompressor
      attr_reader :drive_temperature,
                  :inverter_temperature,
                  :ambient_temperature,
                  :desired_speed,
                  :iz2_desired_speed,
                  :fan_speed,
                  :discharge_pressure,
                  :discharge_temperature,
                  :suction_pressure,
                  :suction_temperature,
                  :saturated_evaporator_discharge_temperature,
                  :superheat_temperature,
                  :subcool_temperature,
                  :eev_open_percentage

      def initialize(abc)
        super(abc, 12)
      end

      def type
        "Variable Speed Drive"
      end

      def registers_to_read
        result = super + [209, 1135..1136, 3000..3001, 3322..3327, 3522, 3524, 3808, 3903..3906]
        result << 564 if abc.iz2?
        result
      end

      def refresh(registers)
        super

        @desired_speed = registers[3000]
        @speed = registers[3001]
        @discharge_pressure = registers[3322]
        @suction_pressure = registers[3323]
        @discharge_temperature = registers[3325]
        @ambient_temperature = registers[3326]
        @drive_temperature = registers[3327]
        @inverter_temperature = registers[3522]
        @fan_speed = registers[3524]
        @eev_open_percentage = registers[3808]
        @suction_temperature = registers[3903]
        @saturated_evaporator_discharge_temperature = registers[3905]
        @superheat_temperature = registers[3906]
        @subcool_temperature = registers[registers[30].include?(:rv) ? 1136 : 1135]

        @iz2_desired_speed = registers[564] if abc.iz2?
      end
    end
  end
end
