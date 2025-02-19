# frozen_string_literal: true

module Aurora
  module_function

  # take an array of ranges, and breaks it up into queryable chunks
  # the ABC limits to 100 registers per read operation
  # there also seem to be issues that some ranges can't be read at
  # the same time as other ranges. possibly correspond to different
  # components?
  def normalize_ranges(ranges)
    registers = ranges.map { |r| Array(r) }.flatten.sort.uniq
    result = []
    totals = []
    run_start = nil
    count = 0
    registers.each_with_index do |r, i|
      run_start ||= r
      next unless i + 1 == registers.length ||
                  r + 1 != registers[i + 1] ||
                  (r - run_start) == 100 ||
                  REGISTER_BREAKPOINTS.include?(r + 1)

      if r == run_start
        result << r
        if (count += 1) == 100
          totals << result
          result = []
          count = 0
        end
      else
        range = run_start..r
        if count + range.count > 100
          totals << result unless result.empty?
          result = []
          count = 0
        end
        count += range.count
        result << range
      end
      run_start = nil
    end
    totals << result unless result.empty?
    totals
  end

  NEGATABLE = ->(v) { (v & 0x8000 == 0x8000) ? v - 0x10000 : v }
  TO_HUNDREDTHS = ->(v) { v.to_f / 100 }
  TO_TENTHS = ->(v) { v.to_f / 10 }
  TO_SIGNED_TENTHS = ->(v) { NEGATABLE.call(v).to_f / 10 }
  TO_LAST_LOCKOUT = ->(v) { (v & 0x8000 == 0x8000) ? v & 0x7fff : nil }

  def from_bitmask(value, flags)
    result = []
    flags.each do |(bit, flag)|
      result << flag if value & bit == bit
      value &= ~bit
    end
    result << format("0x%04x", value) unless value.zero?
    result
  end

  def to_uint32(registers, idx)
    Aurora.logger&.warn("Missing register #{idx + 1}") unless registers[idx + 1]
    (registers[idx] << 16) + registers[idx + 1]
  end

  def to_int32(registers, idx)
    v = to_uint32(registers, idx)
    (v & 0x80000000 == 0x80000000) ? v - 0x100000000 : v
  end

  def to_string(registers, idx, length)
    (idx...(idx + length)).map do |i|
      next "\ufffd" unless registers[i] # missing data? add unicode invalid character

      (registers[i] >> 8).chr + (registers[i] & 0xff).chr
    end.join.sub(/[ \0]+$/, "")
  end

  FAULTS = {
    # ABC/AXB Basic Faults
    1 => "Input Error", # Tstat input error. Autoreset upon condition removal.
    2 => "High Pressure", # HP switch has tripped (>600 psi)
    3 => "Low Pressure", # Low Pressure Switch has tripped (<40 psi for 30 continous sec.)
    4 => "Freeze Detect FP2", # Freeze protection sensor has tripped (<15 or 30 degF for 30 continuous sec.)
    5 => "Freeze Detect FP1", # Freeze protection sensor has tripped (<15 or 30 degF for 30 continuous sec.)
    7 => "Condensate Overflow", # Condensate switch has shown continuity for 30 continuous sec.
    8 => "Over/Under Voltage", # Instantaneous Voltage is out of range. **Controls shut down until resolved.
    9 => "AirF/RPM",
    10 => "Compressor Monitor", # Open Crkt, Run, Start or welded cont
    11 => "FP1/2 Sensor Error",
    12 => "RefPerfrm Error",
    # Miscellaneous
    13 => "Non-Critical AXB Sensor Error", # Any Other Sensor Error
    14 => "Critical AXB Sensor Error", # Sensor Err for EEV or HW
    15 => "Hot Water Limit", # HW over limit or logic lockout. HW pump deactivated.
    16 => "VS Pump Error", # Alert is read from PWM feedback.
    17 => "Communicating Thermostat Error",
    18 => "Non-Critical Communications Error", # Any non-critical com error
    19 => "Critical Communications Error", # Any critical com error. Auto reset upon condition removal
    21 => "Low Loop Pressure", # Loop pressure is below 3 psi for more than 3 minutes
    22 => "Communicating ECM Error",
    23 => "HA Alarm 1", # Closed contact input is present on Dig 2 input - Text is configurable.
    24 => "HA Alarm 2", # Closed contact input is present on Dig 3 input - Text is configurable.
    25 => "AxbEev Error",
    # VS Drive
    41 => "High Drive Temp", # Drive Temp has reached critical High Temp (>239 ̊F/115 ̊C)
    42 => "High Discharge Temp", # Discharge temperature has reached critical high temp (> 280 ̊F/138 ̊C)
    43 => "Low Suction Pressure", # Suction Pressure is critically low (< 28 psig)
    44 => "Low Condensing Pressure", # Condensing pressure is critically low (< 119 psig)
    45 => "High Condensing Pressure", # Condensing pressure is critically high (> 654 psig)
    46 => "Output Power Limit", # Supply Voltage is <208V or Max Pwr is reached due to high pressure
    47 => "EEV ID Comm Error", # Com with EEV is interupted EEV has gone independent mode
    48 => "EEV OD Comm Error", # Com with EEV is interupted EEV has gone independent mode
    49 => "Cabinet Temperature Sensor", # Ambient Temperature (Tamb) is <-76 or > 212 F and out of range or invalid
    51 => "Discharge Temp Sensor", # Discharge Sensor (Sd) is > 280 F or invalid (-76 to 392 F)
    52 => "Suction Pressure Sensor", # Suction Pressure (P0) is invalid (0 to 232 psi)
    53 => "Condensing Pressure Sensor", # Low condensing pressure (PD) or invalid (0 to 870 psi) Retry 10x.
    54 => "Low Supply Voltage", # Supply Voltage is <180 V (190V to reset) or powered off/on too quickly (<30 sec.).
    55 => "Out of Envelope", # Comp Operating out of envelope (P0) more than 90 sec. Retry 10x.
    56 => "Drive Over Current", # Over current tripped by phase loss, earth fault, short circuit, low water flow, low air flow, or major drive fault. # rubocop:disable Layout/LineLength
    57 => "Drive Over/Under Voltage", # DC Link Voltage to compressor is >450vdc or at minimum voltage (<185vdc).
    58 => "High Drive Temp", # Drive Temp has reached critical High Temp >239 F
    59 => "Internal Drive Error", # The MOC has encountered an internal fault or an internal error. Probably fatal.
    61 => "Multiple Safe Mode", # More than one SafeMode condition is present requiring lockout
    # EEV2
    71 => "Loss of Charge", # High superheat and high EEV opening % for a long time will trigger a loss of charge fault
    72 => "Suction Temperature Sensor", # Suction Temperature Sensor is invalid (-76 to 392 F)
    73 => "Leaving Air Temperature Sensor", # Leaving Air Temperature Sensor is invalid (-76 to 392 F)
    74 => "Maximum Operating Pressure", # Suction pressure has exceeded that maximum operating level for 90 sec.
    99 => "System Reset"
  }.freeze

  SMARTGRID_ACTION = {
    0 => :none,
    1 => :unoccupied_set_points,
    2 => :load_shed,
    3 => :capacity_limiting,
    4 => :off_time
  }.freeze

  HA_ALARM = {
    0 => :none,
    1 => :general,
    2 => :security,
    3 => :sump,
    4 => :carbon_monoxide,
    5 => :dirty_filter
  }.freeze

  BRINE_TYPE = Hash.new("Water").merge!(
    485 => "Antifreeze"
  ).freeze

  FLOW_METER_TYPE = Hash.new("Other").merge!(
    0 => "None",
    1 => '3/4"',
    2 => '1"'
  ).freeze

  PUMP_TYPE = Hash.new("Other").merge!(
    0 => "Open Loop",
    1 => "FC1",
    2 => "FC2",
    3 => "VS Pump",
    4 => "VS Pump + 26-99",
    5 => "VS Pump + UPS26-99",
    6 => "FC1_GLNP",
    7 => "FC2_GLNP"
  ).freeze

  PHASE_TYPE = Hash.new("Other").merge!(
    0 => "Single",
    1 => "Three"
  ).freeze

  BLOWER_TYPE = Hash.new("Other").merge!(
    0 => "PSC",
    1 => "ECM 208/230",
    2 => "ECM 265/277",
    3 => "5 Speed ECM 460"
  ).freeze

  ENERGY_MONITOR_TYPE = Hash.new("Other").merge!(
    0 => "None",
    1 => "Compressor Monitor",
    2 => "Energy Monitor"
  ).freeze

  VS_FAULTS = {
    "Under-Voltage Warning" => (71..77),
    "RPM Sensor Signal Fault" => (78..82),
    "Under-Voltage Stop" => (83..87),
    "Rotor Locked" => (88..92),
    "Standby" => (93..99) # should be infinite, but ruby 2.5 doesn't support it
  }.freeze

  def vs_fault(value)
    name = VS_FAULTS.find { |(_, range)| range.include?(value) }&.first
    name ? "#{value} #{name}" : value.to_s
  end

  ACCESSORY_RELAY_SETTINGS = {
    0 => :compressor,
    1 => :slow_opening_water_valve,
    2 => :humidifier,
    3 => :blower
  }.freeze

  def dipswitch_settings(value)
    return :manual if value == 0x7fff

    {
      fp1: (value & 0x01 == 0x01) ? 30 : 15,
      fp2: (value & 0x02 == 0x02) ? 30 : :off,
      reversing_valve: (value & 0x04 == 0x04) ? :o : :b, # cycle to cool on O, or !B
      accessory_relay: ACCESSORY_RELAY_SETTINGS[(value >> 3) & 0x3],
      compressor: (value & 0x20 == 0x20) ? 1 : 2, # single or dual stage compressor
      lockout: (value & 0x40 == 0x40) ? :continuous : :pulse,
      dehumidifier_reheat: (value & 0x80 == 0x80) ? :dehumidifier : :reheat
    }
  end

  COMPONENT_STATUS = {
    1 => :active,
    2 => :added,
    3 => :removed,
    0xffff => :missing
  }.freeze

  SYSTEM_OUTPUTS = {
    0x01 => :cc, # compressor stage 1
    0x02 => :cc2, # compressor stage 2
    0x04 => :rv, # reversing valve (cool instead of heat)
    0x08 => :blower,
    0x10 => :eh1,
    0x20 => :eh2,
    # 0x40 => ??, # this turns on and off quite a bit during normal operation
    # 0x80 => ??, # this turns on occasionally during normal operation; I've only seen it when aux heat is on
    0x200 => :accessory,
    0x400 => :lockout,
    0x800 => :alarm
  }.freeze

  SYSTEM_INPUTS = {
    0x01 => :y1,
    0x02 => :y2,
    0x04 => :w,
    0x08 => :o,
    0x10 => :g,
    0x20 => :dh_rh,
    0x40 => :emergency_shutdown,
    0x200 => :load_shed
  }.freeze

  def status(value)
    result = {
      lps: (value & 0x80 == 0x80) ? :closed : :open,
      hps: (value & 0x100 == 0x100) ? :closed : :open
    }
    SYSTEM_INPUTS.each do |(i, name)|
      result[name] = true if value & i == i
    end
    leftover = value & ~0x03ff
    result[:unknown] = format("0x%04x", leftover) unless leftover.zero?
    result
  end

  VS_DRIVE_DERATE = {
    0x01 => "Drive Over Temp",
    0x04 => "Low Suction Pressure",
    0x10 => "Low Discharge Pressure",
    0x20 => "High Discharge Pressure",
    0x40 => "Output Power Limit"
  }.freeze

  VS_SAFE_MODE = {
    0x01 => "EEV Indoor Failed",
    0x02 => "EEV Outdoor Failed",
    0x04 => "Invalid Ambient Temp"
  }.freeze

  VS_ALARM1 = {
    0x8000 => "Internal Error"
  }.freeze

  VS_ALARM2 = {
    0x0001 => "Multi Safe Modes",
    0x0002 => "Out of Envelope",
    0x0004 => "Over Current",
    0x0008 => "Over Voltage",
    0x0010 => "Drive Over Temp",
    0x0020 => "Under Voltage",
    0x0040 => "High Discharge Temp",
    0x0080 => "Invalid Discharge Temp",
    0x0100 => "OEM Communications Timeout",
    0x0200 => "MOC Safety",
    0x0400 => "DC Under Voltage",
    0x0800 => "Invalid Suction Pressure",
    0x1000 => "Invalid Discharge Pressure",
    0x2000 => "Low Discharge Pressure"
  }.freeze

  VS_EEV2 = {
    0x0010 => "Invalid Suction Temperature",
    0x0020 => "Invalid Leaving Air Temperature",
    0x0040 => "Invalid Suction Pressure"

  }.freeze

  def axb_inputs(value)
    result = {}
    result[:smart_grid] = value & 0x001 == 0x001
    result[:ha1] = value & 0x002 == 0x002
    result[:ha2] = value & 0x004 == 0x004
    result[:pump_slave] = value & 0x008 == 0x008

    result[:mb_address] = (value & 0x010 == 0x010) ? 3 : 4
    result[:sw1_2] = value & 0x020 == 0x020 # future use # rubocop:disable Naming/VariableNumber
    result[:sw1_3] = value & 0x040 == 0x040 # future use # rubocop:disable Naming/VariableNumber
    result[:accessory_relay2] = if value & 0x080 == 0x080 && value & 0x100 == 0x100
                                  :blower
                                elsif value & 0x100 == 0x100
                                  :low_capacity_compressor
                                elsif value & 0x080 == 0x080
                                  :high_capacity_compressor
                                else
                                  :dehumidifier
                                end
    leftover = value & ~0x1ff
    result[:unknown] = format("0x%04x", leftover) unless leftover.zero?
    result
  end

  AXB_OUTPUTS = {
    0x01 => :dhw,
    0x02 => :loop_pump,
    0x04 => :diverting_valve,
    0x08 => :dehumidifer_reheat,
    0x10 => :accessory2
  }.freeze

  HEATING_MODE = {
    0 => :off,
    1 => :auto,
    2 => :cool,
    3 => :heat,
    4 => :eheat
  }.freeze

  FAN_MODE = {
    0 => :auto,
    1 => :continuous,
    2 => :intermittent
  }.freeze

  HUMIDIFIER_SETTINGS = {
    0x4000 => :auto_dehumidification,
    0x8000 => :auto_humidification
  }.freeze

  INVERSE_HUMIDIFIER_SETTINGS = {
    0x4000 => :manual_dehumidification,
    0x8000 => :manual_humidification
  }.freeze

  ZONE_SIZES = {
    0 => 0,
    1 => 25,
    2 => 45,
    3 => 70
  }.freeze

  CALLS = {
    0x0 => :standby,
    0x1 => :unknown1,
    0x2 => :h1,
    0x3 => :h2,
    0x4 => :h3,
    0x5 => :c1,
    0x6 => :c2,
    0x7 => :unknown7
  }.freeze

  def manual_operation(value)
    return :off if value == 0x7fff

    result = {
      mode: (value & 0x100 == 0x100) ? :cooling : :heating
    }
    result[:aux_heat] = true if value & 0x200 == 0x200
    result[:compressor_speed] = value & 0xf
    result[:blower_speed] = value & 0xf0
    result[:blower_speed] = :with_compressor if value & 0xf0 == 0xf0
    leftover = value & ~0x03ff
    result[:unknown] = format("0x%04x", leftover) unless leftover.zero?
    result
  end

  def vs_manual_control(value)
    return :off if value == 0x7fff

    value
  end

  def thermostat_override(value)
    return [:off] if value == 0x7fff

    from_bitmask(value, SYSTEM_INPUTS)
  end

  def iz2_demand(value)
    {
      fan_demand: value >> 8,
      unit_demand: value & 0xff
    }
  end

  def iz2_fan_desired(value)
    case value
    when 1 then 25
    when 2 then 40
    when 3 then 55
    when 4 then 70
    when 5 then 85
    when 6 then 100
    else value
    end
  end

  def thermostat_configuration2(value)
    result = {
      mode: HEATING_MODE[(value >> 8) & 0x07]
    }
    leftover = value & ~0x0700
    result[:unknown] = format("0x%04x", leftover) unless leftover.zero?
    result
  end

  def zone_configuration1(value)
    fan = if value & 0x80 == 0x80
            :continuous
          elsif value & 0x100 == 0x100
            :intermittent
          else
            :auto
          end
    result = {
      fan: fan,
      on_time: ((value >> 9) & 0x7) * 5,
      off_time: (((value >> 12) & 0x7) + 1) * 5,
      cooling_target_temperature: ((value & 0x7e) >> 1) + 36,
      heating_target_temperature_carry: value & 0x01
    }
    leftover = value & ~0x7fff
    result[:unknown] = format("0x%04x", leftover) unless leftover.zero?
    result
  end

  def zone_configuration2(registers, key)
    prior_v = registers[key - 1] if registers.key?(key - 1)
    v = registers[key]
    result = {
      call: CALLS[(v >> 1) & 0x7],
      mode: HEATING_MODE[(v >> 8) & 0x03],
      damper: (v & 0x10 == 0x10) ? :open : :closed
    }
    if prior_v
      carry = prior_v.is_a?(Hash) ? prior_v[:heating_target_temperature_carry] : v & 0x01
      result[:heating_target_temperature] = ((carry << 5) | ((v & 0xf800) >> 11)) + 36
    end
    leftover = v & ~0xfb1e
    result[:unknown] = format("0x%04x", leftover) unless leftover.zero?
    result
  end

  # hi order byte is normalized zone size
  def zone_configuration3(value)
    size = (value >> 3) & 0x3
    result = {
      zone_priority: value.allbits?(0x20) ? :economy : :comfort,
      zone_size: ZONE_SIZES[size],
      normalized_size: value >> 8
    }
    leftover = value & ~0xff38
    result[:unknown] = format("0x%04x", leftover) unless leftover.zero?
    result
  end

  # intermittent on time allowed: 0, 5, 10, 15, 20
  # intermittent off time allowed: 5, 10, 15, 20, 25, 30, 35, 40

  REGISTER_CONVERTERS = {
    TO_HUNDREDTHS => [2, 3, 417, 418, 801, 804, 807, 813, 816, 817, 819, 820, 825, 828],
    method(:dipswitch_settings) => [4, 33],
    # rubocop:disable Layout/MultilineArrayLineBreaks
    TO_TENTHS => [401, 419, 745, 746, 901,
                  1105, 1106, 1107, 1108, 1115, 1116, 1117, 1119,
                  3322, 3323,
                  12_619, 12_620,
                  21_203, 21_204,
                  21_212, 21_213,
                  21_221, 21_222,
                  21_230, 22_131,
                  21_239, 21_240,
                  21_248, 21_249],
    TO_SIGNED_TENTHS => [19, 20, 501, 502, 567, 740, 742, 747, 900, 903,
                         1109, 1110, 1111, 1112, 1113, 1114, 1124, 1125, 1134, 1135, 1136,
                         3325, 3326, 3327, 3330, 3522, 3903, 3905, 3906,
                         31_003, 31_007, 31_010, 31_013, 31_016, 31_019, 31_022],
    # rubocop:enable Layout/MultilineArrayLineBreaks
    TO_LAST_LOCKOUT => [26],
    ->(v) { from_bitmask(v, SYSTEM_OUTPUTS) } => [27, 30],
    ->(v) { from_bitmask(v, SYSTEM_INPUTS) } => [28],
    method(:status) => [31],
    method(:thermostat_override) => [32],
    ->(v) { !v.zero? } => [45, 362, 400],
    ->(registers, idx) { to_string(registers, idx, 4) } => [88],
    ->(registers, idx) { to_string(registers, idx, 12) } => [92],
    ->(registers, idx) { to_string(registers, idx, 5) } => [105],
    ->(v) { from_bitmask(v, VS_DRIVE_DERATE) } => [214, 3223],
    ->(v) { from_bitmask(v, VS_SAFE_MODE) } => [216, 3225],
    ->(v) { from_bitmask(v, VS_ALARM1) } => [217, 3226],
    ->(v) { from_bitmask(v, VS_ALARM2) } => [218, 3227],
    ->(v) { from_bitmask(v, VS_EEV2) } => [280, 3804],
    method(:vs_manual_control) => [323],
    NEGATABLE => [346],
    ->(v) { BRINE_TYPE[v] } => [402],
    ->(v) { FLOW_METER_TYPE[v] } => [403],
    ->(v) { BLOWER_TYPE[v] } => [404],
    ->(v) { v.zero? ? :closed : :open } => [405, 408, 410],
    ->(v) { SMARTGRID_ACTION[v] } => [406],
    ->(v) { HA_ALARM[v] } => [409, 411],
    ->(v) { ENERGY_MONITOR_TYPE[v] } => [412],
    ->(v) { PUMP_TYPE[v] } => [413],
    ->(v) { PHASE_TYPE[v] } => [416],
    method(:iz2_fan_desired) => [565],
    ->(registers, idx) { to_string(registers, idx, 8) } => [710],
    ->(v) { COMPONENT_STATUS[v] } => [800, 803, 806, 812, 815, 818, 824, 827],
    method(:axb_inputs) => [1103],
    ->(v) { from_bitmask(v, AXB_OUTPUTS) } => [1104],
    method(:to_uint32) => [1146, 1148, 1150, 1152, 1164, 3422, 3424],
    method(:to_int32) => [1154, 1156],
    method(:manual_operation) => [3002],
    method(:thermostat_configuration2) => [12_006],
    ->(v) { HEATING_MODE[v] } => [12_606, 21_202, 21_211, 21_220, 21_229, 21_238, 21_247],
    ->(v) { FAN_MODE[v] } => [12_621, 21_205, 21_214, 21_223, 21_232, 21_241, 21_250],
    ->(v) { from_bitmask(v, HUMIDIFIER_SETTINGS) } => [12_309, 21_114, 31_109],
    ->(v) { { humidification_target: v >> 8, dehumidification_target: v & 0xff } } => [12_310, 21_115, 31_110],
    method(:iz2_demand) => [31_005],
    method(:zone_configuration1) => [12_005, 31_008, 31_011, 31_014, 31_017, 31_020, 31_023],
    method(:zone_configuration2) => [31_009, 31_012, 31_015, 31_018, 31_021, 31_024],
    method(:zone_configuration3) => [31_200, 31_203, 31_206, 31_209, 31_212, 31_215],
    ->(registers, idx) { to_string(registers, idx, 13) } => [31_400],
    ->(registers, idx) { to_string(registers, idx, 8) } => [31_413],
    ->(registers, idx) { to_string(registers, idx, 13) } => [31_421],
    ->(registers, idx) { to_string(registers, idx, 13) } => [31_434],
    ->(registers, idx) { to_string(registers, idx, 13) } => [31_447],
    ->(registers, idx) { to_string(registers, idx, 13) } => [31_460]
  }.freeze

  REGISTER_FORMATS = {
    "%ds" => [1, 6, 9, 15, 84, 85, 110],
    "%dV" => [16, 112, 3331, 3424, 3523],
    # rubocop:disable Layout/MultilineArrayLineBreaks
    "%0.1f°F" => [19, 20, 401, 501, 502, 567, 740, 742, 745, 746, 747, 900, 903,
                  1109, 1110, 1111, 1112, 1113, 1114, 1124, 1125, 1134, 1135, 1136,
                  3325, 3326, 3327, 3330, 3522, 3903, 3905, 3906,
                  12_619, 12_620,
                  21_203, 21_204,
                  21_212, 21_213,
                  21_221, 21_222,
                  21_230, 21_231,
                  21_239, 21_240,
                  21_248, 21_249,
                  31_003,
                  31_007, 31_010, 31_013, 31_016, 31_019, 31_022],
    # rubocop:enable Layout/MultilineArrayLineBreaks
    "E%d" => [25, 26],
    "%d%%" => [282, 321, 322, 325, 346, 565, 741, 908, 1126, 3332, 3524, 3808],
    "%0.1f psi" => [419, 901, 1115, 1116, 1119, 3322, 3323],
    "%0.1fA" => [1105, 1106, 1107, 1108],
    "%0.1fgpm" => [1117],
    "%dW" => [1146, 1148, 1150, 1152, 1164, 3422],
    "%dBtuh" => [1154, 1156]
  }.freeze

  def ignore(*range)
    range = range.first if range.length == 1
    range = [range] if range.is_a?(Integer)
    range.zip(Array.new(range.count)).to_h
  end

  def faults(range)
    range.map do |i|
      name = FAULTS[i % 100]
      name = " (#{name})" if name
      [i, "E#{i % 100}#{name}"]
    end.to_h
  end

  def zone_registers
    (1..6).map do |i|
      base1 = 21_202 + ((i - 1) * 9)
      base2 = 31_007 + ((i - 1) * 3)
      base3 = 31_200 + ((i - 1) * 3)
      {
        base1 => "Zone #{i} Heating Mode (write)",
        (base1 + 1) => "Zone #{i} Heating Setpoint (write)",
        (base1 + 2) => "Zone #{i} Cooling Setpoint (write)",
        (base1 + 3) => "Zone #{i} Fan Mode (write)",
        (base1 + 4) => "Zone #{i} Intermittent Fan On Time (write)",
        (base1 + 5) => "Zone #{i} Intermittent Fan Off Time (write)",
        base2 => "Zone #{i} Ambient Temperature",
        (base2 + 1) => "Zone #{i} Configuration 1",
        (base2 + 2) => "Zone #{i} Configuration 2",
        base3 => "Zone #{i} Configuration 3"
      }
    end.inject({}, &:merge)
  end

  WRITEABLE = [112, 340, 341, 342, 346, 347].freeze

  # these are the valid ranges (i.e. the ABC will return _some_ value)
  # * means 6 sequential ranges of equal size (i.e. must be repeated for each
  # IZ2 zone)
  # ==================================================================
  REGISTER_RANGES = [
    0..155,
    170..253,
    260..260,
    280..288,
    300..301,
    320..326,
    340..348,
    360..368,
    400..419,
    440..516,
    550..573,
    600..749,
    800..913,
    1090..1165,
    1200..1263,
    2000..2026,
    2100..2129,
    2800..2849,
    2900..2915,
    2950..2959,
    3000..3003,
    3020..3030,
    3040..3049,
    3060..3063,
    3100..3105,
    3108..3115,
    3118..3119,
    3200..3253,
    3300..3332,
    3400..3431,
    3500..3524,
    3600..3609,
    3618..3634,
    3700..3714,
    3800..3809,
    3818..3834,
    3900..3914,
    12_000..12_019,
    12_098..12_099,
    12_100..12_119,
    12_200..12_239,
    12_300..12_319,
    12_400..12_569,
    12_600..12_639,
    12_700..12_799,
    20_000..20_099,
    21_100..21_136,
    21_200..21_265,
    21_400..21_472,
    21_500..21_589,
    22_100..22_162, # *
    22_200..22_262, # *
    22_300..22_362, # *
    22_400..22_462, # *
    22_500..22_562, # *
    22_600..22_662, # *
    30_000..30_099,
    31_000..31_034,
    31_100..31_129,
    31_200..31_229,
    31_300..31_329,
    31_400..31_472,
    32_100..32_162, # *
    32_200..32_262, # *
    32_300..32_362, # *
    32_400..32_462, # *
    32_500..32_562, # *
    32_600..32_662, # *
    60_050..60_053,
    60_100..60_109,
    60_200..60_200,
    61_000..61_009
  ].freeze

  # see normalize_ranges
  REGISTER_BREAKPOINTS = [
    12_100,
    12_500
  ].freeze

  REGISTER_NAMES = {
    0 => "Test Mode Flag", # 0x100 for enabled; this might have other flags
    1 => "Random Start Delay",
    2 => "ABC Program Version",
    3 => "??? Version?",
    4 => "DIP Switch Override",
    6 => "Compressor Anti-Short Cycle Delay",
    8 => "ABC Program Revision",
    9 => "Compressor Minimum Run Time",
    15 => "Blower Off Delay",
    16 => "Line Voltage",
    17 => "Aux/E Heat Staging Delay", # this is how long aux/eheat have been requested in seconds
    # when in eheat mode (explicit on the thermostat), it will stage up to eh2 after 130s
    # when in aux mode (thermostat set to heat; compressor at full capacity), it will stage up to eh2 after 310s
    19 => "Cooling Liquid Line Temperature (FP1)",
    20 => "Air Coil Temperature (FP2)",
    21 => "Condensate", # >= 270 normal, otherwise fault
    25 => "Last Fault Number", # high bit set if locked out
    26 => "Last Lockout",
    27 => "System Outputs (At Last Lockout)",
    28 => "System Inputs (At Last Lockout)",
    30 => "System Outputs",
    31 => "Status",
    32 => "Thermostat Input Override",
    33 => "DIP Switch Status",
    36 => "ABC Board Rev",
    45 => "Test Mode (write)", # 1 to enable
    47 => "Clear Fault History", # 0x5555 to clear
    50 => "ECM Speed Low (== 5)",
    51 => "ECM Speed Med (== 5)",
    52 => "ECM Speed High (== 5)",
    54 => "ECM Speed Actual",
    84 => "Slow Opening Water Valve Delay",
    85 => "Test Mode Timer",
    88 => "ABC Program",
    92 => "Model Number",
    105 => "Serial Number",
    110 => "Reheat Delay",
    112 => "Line Voltage Setting",
    201 => "Discharge Pressure", # I can't figure out how this number is represented;
    203 => "Suction Pressure",
    205 => "Discharge Temperature",
    207 => "Loop Entering Water Temperature",
    209 => "Compressor Ambient Temperature",
    211 => "VS Drive Details (General 1)",
    212 => "VS Drive Details (General 2)",
    213 => "VS Drive Details (Derate 1)",
    214 => "VS Drive Details (Derate 2)",
    215 => "VS Drive Details (Safemode 1)",
    216 => "VS Drive Details (Safemode 2)",
    217 => "VS Drive Details (Alarm 1)",
    218 => "VS Drive Details (Alarm 2)",
    280 => "EEV2 Ctl",
    281 => "EEV Superheat", # ?? data format
    282 => "EEV Open %",
    283 => "Suction Temperature", ## ?? data format
    284 => "Saturated Suction Temperature", ## ?? data format
    321 => "VS Pump Min",
    322 => "VS Pump Max",
    323 => "VS Pump Speed Manual Control",
    325 => "VS Pump Output",
    326 => "VS Pump Fault",
    340 => "Blower Only Speed",
    341 => "Lo Compressor ECM Speed",
    342 => "Hi Compressor ECM Speed",
    344 => "ECM Speed",
    346 => "Cooling Airflow Adjustment",
    347 => "Aux Heat ECM Speed",
    362 => "Active Dehumidify", # any value is true
    400 => "DHW Enabled",
    401 => "DHW Setpoint",
    402 => "Brine Type",
    403 => "Flow Meter Type",
    404 => "Blower Type",
    405 => "SmartGrid Trigger",
    406 => "SmartGrid Action", # 0/1 for 1/2; see 414
    407 => "Off Time Length",
    408 => "HA Alarm 1 Trigger",
    409 => "HA Alarm 1 Action",
    410 => "HA Alarm 2 Trigger",
    411 => "HA Alarm 2 Action",
    412 => "Energy Monitor", # 0 none, 1 compressor monitor, 2 energy monitor
    413 => "Pump Type",
    414 => "On Peak/SmartGrid", # 0x0001 only
    416 => "Energy Phase Type",
    417 => "Power Adjustment Factor L",
    418 => "Power Adjustment Factor H",
    419 => "Loop Pressure Trip",
    460 => "IZ2 Heartbeat?",
    461 => "IZ2 Heartbeat?",
    462 => "IZ2 Status", # 5 when online; 1 when in setup mode
    483 => "Number of IZ2 Zones",
    501 => "Set Point", # only read by AID tool? this is _not_ heating/cooling set point
    502 => "Ambient Temperature",
    564 => "IZ2 Compressor Speed Desired",
    565 => "IZ2 Blower % Desired",
    567 => "Entering Air",
    710 => "Fault Description",
    740 => "Entering Air",
    741 => "Relative Humidity",
    742 => "Outdoor Temperature",
    745 => "Heating Set Point",
    746 => "Cooling Set Point",
    747 => "Ambient Temperature", # from communicating thermostat? but set to 0 when mode is off?
    800 => "Thermostat Installed",
    801 => "Thermostat Version",
    802 => "Thermostat Revision",
    803 => "??? Installed",
    804 => "??? Version",
    805 => "??? Revision",
    806 => "AXB Installed",
    807 => "AXB Version",
    808 => "AXB Revision",
    809 => "AHB Installed",
    810 => "AHB Version",
    811 => "AHB Revision",
    812 => "IZ2 Installed",
    813 => "IZ2 Version",
    814 => "IZ2 Revision",
    815 => "AOC Installed",
    816 => "AOC Version",
    817 => "AOC Revision",
    818 => "MOC Installed",
    819 => "MOC Version",
    820 => "MOC Revision",
    824 => "EEV2 Installed",
    825 => "EEV2 Version",
    826 => "EEV2 Revision",
    827 => "AWL Installed",
    828 => "AWL Version",
    829 => "AWL Revision",
    900 => "Leaving Air",
    901 => "Suction Pressure",
    903 => "SuperHeat Temperature",
    908 => "EEV Open %",
    909 => "SubCooling (Cooling)",
    1103 => "AXB Inputs",
    1104 => "AXB Outputs",
    1105 => "Blower Amps",
    1106 => "Aux Amps",
    1107 => "Compressor 1 Amps",
    1108 => "Compressor 2 Amps",
    1109 => "Heating Liquid Line Temperature",
    1110 => "Leaving Water",
    1111 => "Entering Water",
    1112 => "Leaving Air Temperature",
    1113 => "Suction Temperature",
    1114 => "DHW Temperature",
    1115 => "Discharge Pressure",
    1116 => "Suction Pressure",
    1117 => "Waterflow",
    1119 => "Loop Pressure", # only valid < 1000psi
    1124 => "Saturated Evaporator Temperature",
    1125 => "SuperHeat",
    1126 => "Vaport Injector Open %",
    1134 => "Saturated Condensor Discharge Temperature",
    1135 => "SubCooling (Heating)",
    1136 => "SubCooling (Cooling)",
    1146 => "Compressor Watts",
    1148 => "Blower Watts",
    1150 => "Aux Watts",
    1152 => "Total Watts",
    1154 => "Heat of Extraction",
    1156 => "Heat of Rejection",
    1164 => "Pump Watts",
    # this combines thermostat/iz2 desired speed with manual operation override
    3000 => "Compressor Speed Desired",
    # this shows the actual speed
    # it can differ from desired during a ramp to the desired speed, or
    # the periodic ramp up to speed 6 that's not visible in the desired speed
    3001 => "Compressor Speed Actual",
    3002 => "Manual Operation",
    3027 => "Compressor Speed",
    3220 => "VS Drive Details (General 1)",
    3221 => "VS Drive Details (General 2)",
    3222 => "VS Drive Details (Derate 1)",
    3223 => "VS Drive Details (Derate 2)",
    3224 => "VS Drive Details (Safemode 1)",
    3225 => "VS Drive Details (Safemode 2)",
    3226 => "VS Drive Details (Alarm 1)",
    3227 => "VS Drive Details (Alarm 2)",
    3322 => "VS Drive Discharge Pressure",
    3323 => "VS Drive Suction Pressure",
    3325 => "VS Drive Discharge Temperature",
    3326 => "VS Drive Compressor Ambient Temperature",
    3327 => "VS Drive Temperature",
    3330 => "VS Drive Entering Water Temperature",
    3331 => "VS Drive Line Voltage",
    3332 => "VS Drive Thermo Power",
    3422 => "VS Drive Compressor Power",
    3424 => "VS Drive Supply Voltage",
    3522 => "VS Drive Inverter Temperature",
    3523 => "VS Drive UDC Voltage",
    3524 => "VS Drive Fan Speed",
    3804 => "VS Drive Details (EEV2 Ctl)",
    3808 => "VS Drive EEV2 % Open",
    3903 => "VS Drive Suction Temperature",
    3904 => "VS Drive Leaving Air Temperature?",
    3905 => "VS Drive Saturated Evaporator Discharge Temperature",
    3906 => "VS Drive SuperHeat Temperature",
    12_005 => "Fan Configuration",
    12_006 => "Heating Mode",
    12_309 => "De/Humidifier Mode",
    12_310 => "De/Humidifier Setpoints",
    12_606 => "Heating Mode (write)",
    12_619 => "Heating Setpoint (write)",
    12_620 => "Cooling Setpoint (write)",
    12_621 => "Fan Mode (write)",
    12_622 => "Intermittent Fan On Time (write)",
    12_623 => "Intermittent Fan Off Time (write)",
    21_114 => "IZ2 De/Humidifier Mode (write)",
    21_115 => "IZ2 De/Humidifier Setpoints (write)",
    31_003 => "IZ2 Outdoor Temperature",
    31_005 => "IZ2 Demand",
    31_109 => "De/Humidifier Mode",
    31_110 => "Manual De/Humidification Setpoints",
    31_400 => "Dealer Name",
    31_413 => "Dealer Phone",
    31_421 => "Dealer Address 1",
    31_434 => "Dealer Address 2",
    31_447 => "Dealer Email",
    31_460 => "Dealer Website"
  }.merge(ignore(89..91))
                   .merge(ignore(93..104))
                   .merge(ignore(106..109))
                   .merge(faults(601..699))
                   .merge(ignore(711..717))
                   .merge(zone_registers)
                   .merge(ignore(1147, 1149, 1151, 1153, 1155, 1157, 1165))
                   .merge(ignore(3423, 3425))
                   .merge(ignore(31_401..31_412))
                   .merge(ignore(31_414..31_420))
                   .merge(ignore(31_422..31_433))
                   .merge(ignore(31_435..31_446))
                   .merge(ignore(31_447..31_459))
                   .merge(ignore(31_461..31_472))

  def transform_registers(registers)
    registers.each do |(k, v)|
      value_proc = REGISTER_CONVERTERS.find { |(_, z)| z.include?(k) }&.first
      next unless value_proc

      value = (value_proc.arity == 2) ? value_proc.call(registers, k) : value_proc.call(v)
      registers[k] = value
    end
    registers
  end

  def read_all_registers(modbus_slave)
    result = []
    REGISTER_RANGES.each do |range|
      # read at most 100 at a time
      range.each_slice(100) do |keys|
        result.concat(modbus_slave.holding_registers[keys.first..keys.last])
      end
    end
    REGISTER_RANGES.map(&:to_a).flatten.zip(result).to_h
  end

  def diff_registers(lhs, rhs)
    diff = {}
    (lhs.keys | rhs.keys).each do |k|
      diff[k] = rhs[k] if lhs[k] != rhs[k]
    end
    diff
  end

  def print_registers(registers)
    result = [] unless block_given?
    registers.each do |(k, value)|
      # ignored
      next if REGISTER_NAMES.key?(k) && REGISTER_NAMES[k].nil?

      name = REGISTER_NAMES[k]

      value_proc = REGISTER_CONVERTERS.find { |(_, z)| z.include?(k) }&.first || ->(v) { v }
      format = REGISTER_FORMATS.find { |(_, z)| z.include?(k) }&.first || "%s"
      format = "%1$d (0x%1$04x)" unless name

      value = (value_proc.arity == 2) ? value_proc.call(registers, k) : value_proc.call(value)
      value = value.join(", ") if value.is_a?(Array)
      value = format(format, value) if value

      name ||= "???"

      full_value = "#{name} (#{k}): #{value}"
      if block_given?
        yield(k, full_value)
      else
        result << full_value
      end
    end
    result.join("\n") unless block_given?
  end
end
