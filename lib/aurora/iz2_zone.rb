module Aurora
  class IZ2Zone
    attr_reader :zone_number,
      :target_mode,
      :current_mode,
      :target_fan_mode,
      :current_fan_mode,
      :fan_intermittent_on,
      :fan_intermitten_off,
      :priority,
      :size, :normalized_size,
      :ambient_temperature,
      :cooling_target_temperature,
      :heating_target_temperature

    def initialize(abc, zone_number)
      @abc = abc
      @zone_number = zone_number
    end

    def refresh(registers)
      @ambient_temperature = registers[31007 + (zone_number - 1) * 3]
      @heating_target_temperature = registers[21203 + (zone_number - 1) * 9]
      @cooling_target_temperature = registers[21204 + (zone_number - 1) * 9]

      config1 = registers[31008 + (zone_number - 1) * 3]
      status = registers[31009 + (zone_number - 1) * 3]
      config2 = registers[31200 + (zone_number - 1) * 3]

      @target_mode = status[:mode]
      @current_mode = status[:call]
      @current_fan_mode = status[:damper] == :open

      @target_fan_mode = config1[:fan]
      @fan_intermittent_on = config1[:fan_on]
      @fan_intermitten_off = config1[:fan_off]
      @priority = config2[:zone_priority]
      @size = config2[:zone_size]
      @normalized_size = config2[:normalized_size]
    end

    def inspect
      "#<Aurora::IZ2Zone #{(instance_variables - [:@abc]).map { |iv| "#{iv}=#{instance_variable_get(iv).inspect}" }.join(', ')}>"
    end
  end
end
