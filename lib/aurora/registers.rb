module Aurora
  extend self

  TO_HUNDREDTHS = ->(v) { v.to_f / 100 }
  TO_TENTHS = ->(v) { v.to_f / 10 }
  TO_LAST_LOCKOUT = ->(v) { v & 0x8000 == 0x8000 ? v & 0x7fff : nil }
  NEGATABLE = ->(v) { v & 0x8000 == 0x8000 ? v - 0x10000 : v }

  def from_bitmask(v, flags)
    "0x%0x4d" % v
  end

  def to_string(registers, idx, length)
    (idx...(idx + length)).map do |i|
    (registers[i] >> 8).chr + (registers[i] & 0xff).chr
    end.join.strip
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

  REGISTER_CONVERTERS = {
    TO_HUNDREDTHS => [2, 3],
    TO_TENTHS => [19, 20, 567, 1105, 1106, 1107, 1108, 1110, 1111, 1114, 1117],
    TO_LAST_LOCKOUT => [26],
    ->(v) { from_bitmask(v, SYSTEM_OUTPUTS) } => [30],
    ->(v) { from_bitmask(v, STATUS) } => [31],
    ->(registers, idx) { to_string(registers, idx, 4) } => [88],
    ->(registers, idx) { to_string(registers, idx, 12) } => [92],
    ->(registers, idx) { to_string(registers, idx, 5) } => [105],
    NEGATABLE => [346, 1146],
    ->(v) { from_bitmask(v, AXB_INPUTS) } => [1103],
    ->(v) { from_bitmask(v, AXB_OUTPUTS) } => [1104]
  }

  REGISTER_FORMATS = {
    "%dV" => [16],
    "%0.1fºF" => [19, 20, 567, 1110, 1111, 1114],
    "E%d" => [25, 26],
    "%d%%" => [346],
    "%0.1fA" => [1105, 1106, 1107, 1108],
    "%0.1fgpm" => [1117],
    "%dW" => [1147, 1149, 1151, 1153, 1165]
  }

  def ignore(range)
    range.zip(Array.new(range.count)).to_h
  end

  def faults(range)
    range.map { |i| [i, "E#{i}"] }.to_h
  end

  REGISTER_NAMES = {
    2 => "ABC Program Version",
    3 => "? Program Version",
    8 => "Unit Type?",
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
    211 => "VS Drive Details (General 1)",
    212 => "VS Drive Details (General 2)",
    213 => "VS Drive Details (Derate 1)",
    214 => "VS Drive Details (Derate 2)",
    215 => "VS Drive Details (Safemode 1)",
    216 => "VS Drive Details (Safemode 2)",
    217 => "VS Drive Details (Alarm 1)",
    218 => "VS Drive Details (Alarm 2)",
    280 => "EEV2 Ctl",
    340 => "Blower Only Speed",
    341 => "Lo Compressor ECM Speed",
    342 => "Hi Compressor ECM Speed",
    346 => "ECM Clg",
    347 => "Aux Heat ECM Speed",
    567 => "Entering Air",
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
    1147 => "Compressor Watts",
    1149 => "Blower Watts",
    1151 => "Aux Watts",
    1153 => "Total Watts",
    1165 => "VS Pump Watts",
  }.merge(ignore(89..91)).
    merge(ignore(93..104)).
    merge(ignore(106..109)).
    merge(faults(601..699))


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
