# frozen_string_literal: true

RSpec.describe Aurora::IZ2Zone do
  let(:zone1) { described_class.new(instance_double(Aurora::ABCClient), 1) }

  def refresh(zone, registers)
    zone.refresh(Aurora.transform_registers(registers))
  end

  it "reports emergency heat on the MasterStat's target mode" do
    registers = { 31_008 => 0,
                  31_009 => 0x6418,
                  31_200 => 0 }
    refresh(zone1, registers)

    expect(zone1.target_mode).to eq(:eheat)
    expect(zone1.current_mode).to eq(:h3)
    expect(zone1.current_fan_mode).to be(true)
  end
end
