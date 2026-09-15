# frozen_string_literal: true

RSpec.describe Aurora do
  describe "registers" do
    describe ".zone_configuration2" do
      let(:snapshots) { fixture("iz2_emergency_heat") }

      def decode(zone, value)
        register = 31_009 + ((zone - 1) * 3)
        described_class.zone_configuration2({ register => value }, register)
      end

      it "decodes eheat with damper closed" do
        expect(decode(1, 0x2400)).to eq(mode: :eheat, call: :standby, damper: :closed)
      end

      it "decodes eheat with damper open" do
        expect(decode(1, 0x2410)).to eq(mode: :eheat, call: :standby, damper: :open)
      end

      it "decodes eheat with h3 call" do
        expect(decode(1, 0x2418)).to eq(mode: :eheat, call: :h3, damper: :open)
      end

      it "preserves zone 1 auto mode before emergency heat" do
        expect(decode(1, 0x2100)).to eq(mode: :auto, call: :standby, damper: :closed)
      end

      it "preserves zone 2 heat mode and unrelated unknown bits" do
        expect(decode(2, 0x0350)).to eq(mode: :heat, call: :standby, damper: :open, unknown: "0x0040")
      end
    end
  end
end
