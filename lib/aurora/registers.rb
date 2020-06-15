module Aurora
  extend self

  TO_HUNDREDTHS = ->(v) { v.to_f / 100 }
  TO_TENTHS = ->(v) { v.to_f / 10 }
  TO_LAST_LOCKOUT = ->(v) { v & 0x8000 == 0x8000 ? v & 0x7fff : nil }
  NEGATABLE = ->(v) { v & 0x8000 == 0x8000 ? v - 0x10000 : v }

  def from_bitmask(v, flags)
    result = []
    flags.each do |(bit, flag)|
      result << flag if v & bit == bit
      v &= ~bit
    end
    result << "0x%04x" % v if v != 0
    result.join(", ")
  end

  def to_string(registers, idx, length)
    (idx...(idx + length)).map do |i|
      (registers[i] >> 8).chr + (registers[i] & 0xff).chr
    end.join.sub(/[ \0]+$/, '')
  end

  SYSTEM_OUTPUTS = {
    0x40 => "RV?",
    0x20 => "EH2?",
    0x10 => "EH1?",
    0x02 => "CC2?",
    0x01 => "CC1?"
  }

  STATUS = {
    0x20 => "DH?",
    0x10 => "Fan?",
    0x08 => "Cool/Heat?",
    0x04 => "EHeat?",
    0x02 => "Stage 2?",
    0x01 => "Stage 1?"
  }

  AXB_INPUTS = {
  }

  AXB_OUTPUTS = {
    0x10 => "Accessor 2",
    0x02 => "Loop Pump",
    0x01 => "DHW"
  }

  HEATING_MODE = {
    0 => :off,
    1 => :auto,
    2 => :cool,
    3 => :heat,
    4 => :eheat
  }

  FAN_MODE = {
    0 => :auto,
    1 => :continuous,
    2 => :intermittent
  }

  HUMIDIFIER_SETTINGS = {
    0x4000 => :auto_dehumidification,
    0x8000 => :auto_humidification,
  }

  INVERSE_HUMIDIFIER_SETTINGS = {
    0x4000 => :manual_dehumidification,
    0x8000 => :manual_humidification,
  }

  ZONE_SIZES = {
    0 => 0,
    1 => 25,
    2 => 45,
    3 => 70,
  }

  CALLS = {
    0x0 => :standby,
    0x1 => :unknown1,
    0x2 => :h1,
    0x3 => :h2,
    0x4 => :h3,
    0x5 => :c1,
    0x6 => :c2,
    0x7 => :unknown7,
  }

  def iz2_demand(v)
    {
      fan_demand: v >> 8,
      unit_demand: v & 0xff,
    }
  end

  def zone_configuration1(v)
    fan = if v & 0x80 == 0x80
      :continuous
    elsif v & 0x100 == 0x100
      :intermittent
    else
      :auto
    end
    result = {
      fan: fan,
      on_time: ((v >> 17) & 0x7) * 5,
      off_time: (((v >> 24) & 0x7) + 1) * 5
    }
    leftover = v & ~0x7f80
    result[:unknown] = "0x%04x" % leftover unless leftover == 0
    result
  end

  # hi order byte is normalized zone size
  def zone_configuration2(v)
    size = (v >> 3 ) & 0x3
    result = {
      zone_priority: (v & 0x20) == 0x20 ? :economy : :comfort,
      zone_size: ZONE_SIZES[size],
      normalized_size: v >> 8,
    }
    leftover = v & ~0xff38
    result[:unknown] = "0x%04x" % leftover unless leftover == 0
    result
  end

  def zone_status(v)
    result = {
      call: CALLS[(v >> 1) & 0x7],
      mode: HEATING_MODE[(v >> 8) & 0x03],
      damper: v & 0x10 == 0x10 ? :open : :closed,
    }
    leftover = v & ~0x031e
    result[:unknown] = "0x%04x" % leftover unless leftover == 0
    result
  end


  # intermittent on time allowed: 0, 5, 10, 15, 20
  # intermittent off time allowed: 5, 10, 15, 20, 25, 30, 35, 40

  REGISTER_CONVERTERS = {
    TO_HUNDREDTHS => [2, 3, 807, 813, 816, 817, 819, 820, 825, 828],
    TO_TENTHS => [19, 20, 401, 567, 740, 900, 1105, 1106, 1107, 1108, 1110, 1111, 1114, 1117, 1134, 1136,
      21203, 21204,
      21212, 21213,
      21221, 21222,
      21230, 22131,
      21239, 21240,
      21248, 21249,
      31003,
      31007, 31010, 31013, 31016, 31019, 31022],
    TO_LAST_LOCKOUT => [26],
    ->(v) { from_bitmask(v, SYSTEM_OUTPUTS) } => [30],
    ->(v) { from_bitmask(v, STATUS) } => [31],
    ->(registers, idx) { to_string(registers, idx, 4) } => [88],
    ->(registers, idx) { to_string(registers, idx, 12) } => [92],
    ->(registers, idx) { to_string(registers, idx, 5) } => [105],
    NEGATABLE => [346, 1146],
    ->(v) { from_bitmask(v, AXB_INPUTS) } => [1103],
    ->(v) { from_bitmask(v, AXB_OUTPUTS) } => [1104],
    ->(v) { TO_TENTHS.call(NEGATABLE.call(v)) } => [1136],
    ->(v) { from_bitmask(v, HUMIDIFIER_SETTINGS) } => [31109],
    ->(v) { { humidification_target: v >> 8, dehumidification_target: v & 0xff } } => [31110],
    method(:iz2_demand) => [31005],
    method(:zone_configuration1) => [31008, 31011, 31014, 31017, 31020, 31023],
    method(:zone_configuration2) => [31200, 31203, 31206, 31209, 31212, 31215],
    method(:zone_status) => [31009, 31012, 31015, 31018, 31021, 31024],
    ->(registers, idx) { to_string(registers, idx, 13) } => [31400],
    ->(registers, idx) { to_string(registers, idx, 8) } => [31413],
    ->(registers, idx) { to_string(registers, idx, 13) } => [31421],
    ->(registers, idx) { to_string(registers, idx, 13) } => [31434],
    ->(registers, idx) { to_string(registers, idx, 13) } => [31447],
    ->(registers, idx) { to_string(registers, idx, 13) } => [31460],
  }

  REGISTER_FORMATS = {
    "%ds" => [6, 15],
    "%dV" => [16, 112],
    "%0.1fºF" => [19, 20, 401, 567, 740, 900, 1110, 1111, 1114, 1134, 1136,
      21203, 21204,
      21212, 21213,
      21221, 21222,
      21230, 22131,
      21239, 21240,
      21248, 21249,
      31003,
      31007, 31010, 31013, 31016, 31019, 31022],
    "E%d" => [25, 26],
    "%d%%" => [321, 322, 346, 741],
    "%0.1fA" => [1105, 1106, 1107, 1108],
    "%0.1fgpm" => [1117],
    "%dW" => [1147, 1149, 1151, 1153, 1165],
    "%dBtuh" => [1157],
  }

  def ignore(range)
    range.zip(Array.new(range.count)).to_h
  end

  def faults(range)
    range.map { |i| [i, "E#{i}"] }.to_h
  end

  def zone_registers
    (1..6).map do |i|
      base1 = 21202 + (i - 1) * 9
      base2 = 31007 + (i - 1) * 3
      base3 = 31200 + (i - 1) * 3
      {
        base1 => "Zone #{i} Heating Mode", # write
        (base1 + 1) => "Zone #{i} Heating Setpoint",
        (base1 + 2) => "Zone #{i} Cooling Setpoint",
        (base1 + 3) => "Zone #{i} Fan Mode", # write
        (base1 + 4) => "Zone #{i} Intermittent Fan On Time", # write
        (base1 + 5) => "Zone #{i} Intermittent Fan Off Time", # write
        base2 => "Zone #{i} Temperature",
        (base2 + 1) => "Zone #{i} Configuration 1",
        (base2 + 2) => "Zone #{i} Status",
        base3 => "Zone #{i} Configuration 2",
      }
    end.inject({}, &:merge)
  end

  WRITEABLE = [112, 340, 341, 342, 346, 347]

  REGISTER_NAMES = {
    2 => "ABC Program Version",
    3 => "IZ2 Version?",
    6 => "Comp ASC Delay",
    8 => "Unit Type?",
    15 => "Blower Off Delay",
    16 => "Line Voltage",
    19 => "FP1",
    20 => "FP2",
    25 => "Last Fault Number",
    26 => "Last Lockout",
    30 => "System Outputs",
    31 => "Status",
    88 => "ABC Program",
    92 => "Model Number",
    105 => "Serial Number",
    112 => "Setup Line Voltage",
    211 => "VS Drive Details (General 1)",
    212 => "VS Drive Details (General 2)",
    213 => "VS Drive Details (Derate 1)",
    214 => "VS Drive Details (Derate 2)",
    215 => "VS Drive Details (Safemode 1)",
    216 => "VS Drive Details (Safemode 2)",
    217 => "VS Drive Details (Alarm 1)",
    218 => "VS Drive Details (Alarm 2)",
    280 => "EEV2 Ctl",
    321 => "VS Pump Min",
    322 => "VS Pump Max",
    340 => "Blower Only Speed",
    341 => "Lo Compressor ECM Speed",
    342 => "Hi Compressor ECM Speed",
    344 => "ECM Speed",
    346 => "Cooling Airflow Adjustment",
    347 => "Aux Heat ECM Speed",
    401 => "DHW Setpoint",
    483 => "Number of IZ2 Zones",
    567 => "Entering Air",
    740 => "Entering Air",
    741 => "Relative Humidity",
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
    1110 => "Leaving Water",
    1111 => "Entering Water",
    1114 => "DHW Temp",
    1117 => "Waterflow",
    1134 => "Sat Cond",
    1136 => "SubCooling",
    1147 => "Compressor Watts",
    1149 => "Blower Watts",
    1151 => "Aux Watts",
    1153 => "Total Watts",
    1157 => "Ht of Rej",
    1165 => "VS Pump Watts",
    3027 => "Compressor Speed",
    31003 => "Outdoor Temp",
    31005 => "IZ2 Demand",
    31109 => "Humidifier Mode", # write to 21114
    31110 => "Manual De/Humidification Target", # write to 21115
    31400 => "Dealer Name",
    31413 => "Dealer Phone",
    31421 => "Dealer Address 1",
    31434 => "Dealer Address 2",
    31447 => "Dealer Email",
    31460 => "Dealer Website",
  }.merge(ignore(89..91)).
    merge(ignore(93..104)).
    merge(ignore(106..109)).
    merge(faults(601..699)).
    merge(zone_registers)


  def print_registers(registers)
    registers.each do |(k, v)|
      # ignored
      next if REGISTER_NAMES.key?(k) && REGISTER_NAMES[k].nil?
      name = REGISTER_NAMES[k]
      value_proc = REGISTER_CONVERTERS.find { |(_, z)| z.include?(k) }&.first || ->(v) { v }
      format = REGISTER_FORMATS.find { |(_, z)| z.include?(k) }&.first || "%s"
      format = "%1$d (0x%1$04x)" unless name
      name ||= "???"
  
      value = value_proc.arity == 2 ? value_proc.call(registers, k) : value_proc.call(v)
      value = sprintf(format, value)
  
      puts "#{name} (#{k}): #{value}"
    end
  end
end
