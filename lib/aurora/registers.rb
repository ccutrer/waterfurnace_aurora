# frozen_string_literal: true

module Aurora
  module_function

  def normalize_ranges(ranges)
    registers = ranges.map { |r| Array(r) }.flatten.sort.uniq
    result = []
    totals = []
    run_start = nil
    count = 0
    registers.each_with_index do |r, i|
      run_start ||= r
      next unless i + 1 == registers.length || r + 1 != registers[i + 1]

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
          totals << result
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

  TO_HUNDREDTHS = ->(v) { v.to_f / 100 }
  TO_TENTHS = ->(v) { v.to_f / 10 }
  TO_LAST_LOCKOUT = ->(v) { v & 0x8000 == 0x8000 ? v & 0x7fff : nil }
  NEGATABLE = ->(v) { v & 0x8000 == 0x8000 ? v - 0x10000 : v }

  def from_bitmask(value, flags)
    result = []
    flags.each do |(bit, flag)|
      result << flag if value & bit == bit
      value &= ~bit
    end
    result << format("0x%04x", value) unless value.zero?
    result
  end

  def to_string(registers, idx, length)
    puts "converting #{idx} of length #{length}"
    (idx...(idx + length)).map do |i|
      (registers[i] >> 8).chr + (registers[i] & 0xff).chr
    end.join.sub(/[ \0]+$/, "")
  end

  FAULTS = {
    1 => "Input Flt Limit",
    2 => "High Pressure",
    3 => "Low Pressure",
    4 => "FP2",
    5 => "FP1",
    7 => "Condensate Limit",
    8 => "Over/Under Voltage",
    9 => "AirF/RPM",
    10 => "CompMon",
    11 => "FP1/2 Snr Limit",
    12 => "RefPerfrm Limit",
    13 => "NCrtAxbSr Limit",
    14 => "CrtAxbSnr Limit",
    15 => "HW Limit",
    16 => "VSPumpFlt Limit",
    17 => "CommTStat Limit",
    18 => "NCritComm Limit",
    19 => "Crit Comm Limit",
    21 => "Low Loop Pressure",
    22 => "ComEcmErr Limit",
    23 => "HAGenAlrm1 Limit",
    24 => "HAGenAlrm2 Limit",
    25 => "AxbEevErr Limit",
    41 => "High Drive Temp Limit",
    42 => "High Discharge Temp Limit",
    43 => "Low Suction Pressure Limit",
    44 => "Low Con Pressure Limit",
    45 => "High Con Pressure Limit",
    46 => "Out Power Limit",
    47 => "EevIDComm Limit",
    48 => "EevODComm Limit",
    49 => "CabTmpSnr Limit",
    51 => "Discharge Temp Sensor Limit",
    52 => "Suction Presure Sensor Limit",
    53 => "Con Pressure Sensor Limit",
    54 => "Low Supply Voltage Limit",
    55 => "OutEnvelp Limit",
    56 => "Suction Pressure Sensor Limit",
    57 => "Drive Over/Under Voltage Limit",
    58 => "High Drive Temp Limit",
    59 => "Internal Drive Error Limit",
    61 => "MultSafm",
    71 => "ChrgLoss",
    72 => "Suction Temp Sensor Limit",
    73 => "Leaving Air Temp Sensor Limit",
    74 => "Maximum Operating Pressure Limit",
    75 => "Charge Loss",
    76 => "Suction Temperatur Sensor Limit",
    77 => "Leaving Air Temperature Sensor Limit",
    78 => "Maximum Operating Pressure Limit"
  }.freeze

  AR_SETTINGS = {
    0 => "Cycle with Compressor",
    1 => "Cycle with Thermostat Humidification Call",
    2 => "Slow Opening Water Valve",
    3 => "Cycle with Blower"
  }.freeze

  def dipswitch_settings(value)
    return :manual if value == 0x7fff

    {
      fp1: value & 0x01 == 0x01 ? "30ºF" : "15ºF",
      fp2: value & 0x02 == 0x02 ? "30ºF" : "15ºF",
      rv: value & 0x04 == 0x04 ? "O" : "B",
      ar: AR_SETTINGS[(value >> 3) & 0x7],
      cc: value & 0x20 == 0x20 ? "Single Stage" : "Dual Stage",
      lo: value & 0x40 == 0x40 ? "Continouous" : "Pulse",
      dh_rh: value & 0x80 == 0x80 ? "Dehumdifier On" : "Reheat On"
    }
  end

  SYSTEM_OUTPUTS = {
    0x01 => :cc, # compressor stage 1
    0x02 => :cc2, # compressor stage 2
    0x04 => :rv, # reversing valve (cool instead of heat)
    0x08 => :blower,
    0x10 => :eh1,
    0x20 => :eh2,
    0x200 => :accessory,
    0x400 => :lockout,
    0x800 => :alarm
  }.freeze

  SYSTEM_INPUTS = {
    0x01 => "Y1",
    0x02 => "Y2",
    0x04 => "W",
    0x08 => "O",
    0x10 => "G",
    0x20 => "Dehumidifer",
    0x40 => "Emergency Shutdown",
    0x200 => "Load Shed"
  }.freeze

  def status(value)
    result = {
      lps: value & 0x80 == 0x80 ? :closed : :open,
      hps: value & 0x100 == 0x100 ? :closed : :open
    }
    result[:load_shed] = true if value & 0x0200 == 0x0200
    result[:emergency_shutdown] = true if value & 0x0040 == 0x0040
    leftover = value & ~0x03c0
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

  AXB_INPUTS = {
  }.freeze

  AXB_OUTPUTS = {
    0x10 => "Accessory 2",
    0x02 => "Loop Pump",
    0x01 => "DHW"
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

  def iz2_demand(value)
    {
      fan_demand: value >> 8,
      unit_demand: value & 0xff
    }
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
      heating_target_temperature_carry: value & 0o1
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
      damper: v & 0x10 == 0x10 ? :open : :closed
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
      zone_priority: (value & 0x20) == 0x20 ? :economy : :comfort,
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
    TO_HUNDREDTHS => [2, 3, 807, 813, 816, 817, 819, 820, 825, 828],
    method(:dipswitch_settings) => [4, 33],
    TO_TENTHS => [19, 20, 401, 567, 740, 745, 746, 900, 1105, 1106, 1107, 1108, 1110, 1111, 1114, 1117, 1134, 1136,
                  21_203, 21_204,
                  21_212, 21_213,
                  21_221, 21_222,
                  21_230, 22_131,
                  21_239, 21_240,
                  21_248, 21_249,
                  31_003,
                  31_007, 31_010, 31_013, 31_016, 31_019, 31_022],
    TO_LAST_LOCKOUT => [26],
    ->(v) { from_bitmask(v, SYSTEM_OUTPUTS) } => [27, 30],
    ->(v) { from_bitmask(v, SYSTEM_INPUTS) } => [28],
    method(:status) => [31],
    ->(registers, idx) { to_string(registers, idx, 4) } => [88],
    ->(registers, idx) { to_string(registers, idx, 12) } => [92],
    ->(registers, idx) { to_string(registers, idx, 5) } => [105],
    ->(v) { from_bitmask(v, VS_DRIVE_DERATE) } => [214],
    ->(v) { from_bitmask(v, VS_SAFE_MODE) } => [216],
    ->(v) { from_bitmask(v, VS_ALARM1) } => [217],
    ->(v) { from_bitmask(v, VS_ALARM2) } => [218],
    ->(v) { from_bitmask(v, VS_EEV2) } => [280],
    NEGATABLE => [346, 1146],
    ->(v) { from_bitmask(v, AXB_INPUTS) } => [1103],
    ->(v) { from_bitmask(v, AXB_OUTPUTS) } => [1104],
    ->(v) { TO_TENTHS.call(NEGATABLE.call(v)) } => [1136],
    ->(v) { HEATING_MODE[v] } => [21_202, 21_211, 21_220, 21_229, 21_238, 21_247],
    ->(v) { FAN_MODE[v] } => [21_205, 21_214, 21_223, 21_232, 21_241, 21_250],
    ->(v) { from_bitmask(v, HUMIDIFIER_SETTINGS) } => [31_109],
    ->(v) { { humidification_target: v >> 8, dehumidification_target: v & 0xff } } => [31_110],
    method(:iz2_demand) => [31_005],
    method(:zone_configuration1) => [31_008, 31_011, 31_014, 31_017, 31_020, 31_023],
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
    "%ds" => [1, 6, 9, 15, 84, 85],
    "%dV" => [16, 112],
    "%0.1fºF" => [19, 20, 401, 567, 740, 745, 746, 900, 1110, 1111, 1114, 1134, 1136,
                  21_203, 21_204,
                  21_212, 21_213,
                  21_221, 21_222,
                  21_230, 21_231,
                  21_239, 21_240,
                  21_248, 21_249,
                  31_003,
                  31_007, 31_010, 31_013, 31_016, 31_019, 31_022],
    "E%d" => [25, 26],
    "%d%%" => [282, 321, 322, 346, 565, 741],
    "%0.1fA" => [1105, 1106, 1107, 1108],
    "%0.1fgpm" => [1117],
    "%dW" => [1147, 1149, 1151, 1153, 1165],
    "%dBtuh" => [1157]
  }.freeze

  def ignore(range)
    range.zip(Array.new(range.count)).to_h
  end

  def faults(range)
    range.map { |i| [i, "E#{i % 100}"] }.to_h
  end

  def zone_registers
    (1..6).map do |i|
      base1 = 21_202 + (i - 1) * 9
      base2 = 31_007 + (i - 1) * 3
      base3 = 31_200 + (i - 1) * 3
      {
        base1 => "Zone #{i} Heating Mode",
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
    lhs.each_key do |k|
      diff[k] = [lhs[k], rhs[k]] if lhs[k] != rhs[k]
    end
    diff
  end

  REGISTER_NAMES = {
    1 => "Random Start Delay",
    2 => "ABC Program Version",
    3 => "IZ2 Version?",
    4 => "DIP Switch Override",
    6 => "Compressor Anti-Short Cycle Delay",
    8 => "Unit Type?",
    9 => "Compressor Minimum Run Time",
    15 => "Blower Off Delay",
    16 => "Line Voltage",
    19 => "FP1",
    20 => "FP2",
    21 => "Condensate", # >= 270 normal, otherwise fault
    25 => "Last Fault Number",
    26 => "Last Lockout",
    27 => "System Outputs (At Last Lockout)",
    28 => "System Inputs (At Last Lockout)",
    30 => "System Outputs",
    31 => "Status",
    33 => "DIP Switch Status",
    50 => "ECM Speed Low (== 5)",
    51 => "ECM Speed Med (== 5)",
    52 => "ECM Speed High (== 5)",
    54 => "ECM Speed Actual",
    84 => "Slow Opening Water Valve Delay",
    85 => "Test Mode Timer",
    88 => "ABC Program",
    92 => "Model Number",
    105 => "Serial Number",
    112 => "Setup Line Voltage",
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
    340 => "Blower Only Speed",
    341 => "Lo Compressor ECM Speed",
    342 => "Hi Compressor ECM Speed",
    344 => "ECM Speed",
    346 => "Cooling Airflow Adjustment",
    347 => "Aux Heat ECM Speed",
    362 => "Active Dehumidify", # any value is true
    401 => "DHW Setpoint",
    414 => "On Peak/SmartGrid 2", # 0x0001 only
    483 => "Number of IZ2 Zones",
    564 => "IZ2 Compressor Speed Desired",
    565 => "IZ2 Blower % Desired",
    567 => "Entering Air",
    740 => "Entering Air",
    741 => "Relative Humidity",
    745 => "Heating Set Point",
    746 => "Cooling Set Point",
    807 => "AXB Version",
    813 => "IZ2 Version?",
    816 => "AOC Version 1?",
    817 => "AOC Version 2?",
    819 => "MOC Version 1?",
    820 => "MOC Version 2?",
    825 => "EEV2 Version",
    828 => "AWL Version",
    900 => "Leaving Air",
    1103 => "AXB Inputs",
    1104 => "AXB Outputs",
    1105 => "Blower Amps",
    1106 => "Aux Amps",
    1107 => "Compressor 1 Amps",
    1108 => "Compressor 2 Amps",
    1109 => "Heating Liquid Line",
    1110 => "Leaving Water",
    1111 => "Entering Water",
    1114 => "DHW Temp",
    1117 => "Waterflow",
    1134 => "Saturated Discharge Temperature",
    1135 => "SubCooling",
    1147 => "Compressor Watts",
    1149 => "Blower Watts",
    1151 => "Aux Watts",
    1153 => "Total Watts",
    1157 => "Ht of Rej",
    1165 => "VS Pump Watts",
    3027 => "Compressor Speed",
    31_003 => "Outdoor Temp",
    31_005 => "IZ2 Demand",
    31_109 => "Humidifier Mode", # write to 21114
    31_110 => "Manual De/Humidification Target", # write to 21115
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
                   .merge(zone_registers)
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

      value = value_proc.arity == 2 ? value_proc.call(registers, k) : value_proc.call(v)
      registers[k] = value
    end
    registers
  end

  def print_registers(registers)
    result = []
    registers.each do |(k, value)|
      # ignored
      next if REGISTER_NAMES.key?(k) && REGISTER_NAMES[k].nil?

      name = REGISTER_NAMES[k]
      value_proc = REGISTER_CONVERTERS.find { |(_, z)| z.include?(k) }&.first || ->(v) { v }
      format = REGISTER_FORMATS.find { |(_, z)| z.include?(k) }&.first || "%s"
      format = "%1$d (0x%1$04x)" unless name
      name ||= "???"

      value = value_proc.arity == 2 ? value_proc.call(registers, k) : value_proc.call(value)
      value = value.join(", ") if value.is_a?(Array)
      value = format(format, value) if value

      result << "#{name} (#{k}): #{value}"
    end
    result.join("\n")
  end
end
