# frozen_string_literal: true

require "aurora/thermostat"

module Aurora
  class IZ2Zone < Thermostat
    attr_reader :zone_number,
                :current_mode,
                :current_fan_mode,
                :fan_intermittent_on,
                :fan_intermittent_off,
                :priority,
                :size, :normalized_size

    def initialize(abc, zone_number)
      super(abc)
      @zone_number = zone_number
    end

    def refresh(registers)
      @ambient_temperature = registers[31_007 + (zone_number - 1) * 3]

      config1 = registers[31_008 + (zone_number - 1) * 3]
      config2 = registers[31_009 + (zone_number - 1) * 3]
      config3 = registers[31_200 + (zone_number - 1) * 3]

      @target_fan_mode = config1[:fan]
      @fan_intermittent_on = config1[:on_time]
      @fan_intermittent_off = config1[:off_time]
      @cooling_target_temperature = config1[:cooling_target_temperature]
      @heating_target_temperature = config2[:heating_target_temperature]
      @target_mode = config2[:mode]
      @current_mode = config2[:call]
      @current_fan_mode = config2[:damper] == :open

      @priority = config3[:zone_priority]
      @size = config3[:zone_size]
      @normalized_size = config3[:normalized_size]
    end

    def target_mode=(value)
      value = Aurora::HEATING_MODE.invert[value]
      return unless value

      @abc.modbus_slave.holding_registers[21_202 + (zone_number - 1) * 9] = value
      @target_mode = Aurora::HEATING_MODE[@abc.modbus_slave.holding_registers[21_202 + (zone_number - 1) * 9]]
    end

    def target_fan_mode=(value)
      value = Aurora::FAN_MODE.invert[value]
      return unless value

      @abc.modbus_slave.holding_registers[21_205 + (zone_number - 1) * 9] = value
      registers = @abc.modbus_slave.read_multiple_holding_registers(31_008 + (zone_number - 1) * 3)
      Aurora.transform_registers(registers)
      @target_fan_mode = registers.first.last[:fan]
    end

    def fan_intermittent_on=(value)
      return unless value >= 0 && value <= 25 && (value % 5).zero?

      @abc.modbus_slave.holding_registers[21_206 + (zone_number - 1) * 9] = value
      registers = @abc.modbus_slave.read_multiple_holding_registers(31_008 + (zone_number - 1) * 3)
      Aurora.transform_registers(registers)
      @fan_intermittent_on = registers.first.last[:on_time]
    end

    def fan_intermittent_off=(value)
      return unless value >= 0 && value <= 40 && (value % 5).zero?

      @abc.modbus_slave.holding_registers[21_207 + (zone_number - 1) * 9] = value
      registers = @abc.modbus_slave.read_multiple_holding_registers(31_008 + (zone_number - 1) * 3)
      Aurora.transform_registers(registers)
      @fan_intermittent_on = registers.first.last[:off_time]
    end

    def heating_target_temperature=(value)
      return unless value >= 40 && value <= 90

      value = (value * 10).to_i
      @abc.modbus_slave.holding_registers[21_203 + (zone_number - 1) * 9] = value

      base = 31_008 + (zone_number - 1) * 3
      registers = @abc.modbus_slave.read_multiple_holding_registers(base..(base + 1))
      Aurora.transform_registers(registers)
      registers[base + 1][:heating_target_temperature]
    end

    def cooling_target_temperature=(value)
      return unless value >= 54 && value <= 99

      value = (value * 10).to_i
      @abc.modbus_slave.holding_registers[21_204 + (zone_number - 1) * 9] = value

      registers = @abc.modbus_slave.read_multiple_holding_registers(31_008 + (zone_number - 1) * 3)
      Aurora.transform_registers(registers)
      registers.first.last[:cooling_target_temperature]
    end
  end
end
