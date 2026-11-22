# frozen_string_literal: true

# The APU mixer (https://www.nesdev.org/wiki/APU_Mixer) through the page's lookup tables (plan 23, decision 5):
# "pulse_table[n] = 95.52 / (8128.0 / n + 100)", indexed by "pulse1 + pulse2" (31 entries), and "tnd_table[n] = 163.67 /
# (24329.0 / n + 100)", indexed by "3 * triangle + 2 * noise + dmc" (203 entries); the output is their sum. "When the
# values for one of the groups are all zero, the result for that group should be treated as zero". The exact formulas,
# "pulse_out = 95.88 / ((8128 / (pulse1 + pulse2)) + 100)" and "tnd_out = 159.79 / (1 / ((triangle / 8227) + (noise /
# 12241) + (dmc / 22638)) + 100)", stay within 0.5% of the tables at the maxima.
RSpec.describe Ruby::Nes::Apu::Mixer do
  describe '.mix' do
    context 'when every channel is silent' do
      it 'is exactly 0' do
        expect(described_class.mix(0, 0, 0, 0, 0)).to eq(0.0)
      end
    end

    context 'when only the first pulse sounds' do
      it 'is the pulse table at its volume' do
        expect(described_class.mix(1, 0, 0, 0, 0)).to be_within(1e-12).of(95.52 / ((8128.0 / 1) + 100))
      end
    end

    context 'when only the second pulse sounds' do
      it 'is the pulse table at its volume' do
        expect(described_class.mix(0, 1, 0, 0, 0)).to be_within(1e-12).of(95.52 / ((8128.0 / 1) + 100))
      end
    end

    context 'when both pulses sound at their maximum' do
      it 'is the pulse table at 30, within 0.5% of the exact formula', :aggregate_failures do
        output = described_class.mix(15, 15, 0, 0, 0)
        expect(output).to be_within(1e-12).of(95.52 / ((8128.0 / 30) + 100))
        expect(output).to be_within(0.005 * output).of(95.88 / ((8128.0 / 30) + 100))
      end
    end

    context 'when only the triangle sounds' do
      it 'is the triangle/noise/DMC table at three times its volume' do
        expect(described_class.mix(0, 0, 1, 0, 0)).to be_within(1e-12).of(163.67 / ((24_329.0 / 3) + 100))
      end
    end

    context 'when only the noise sounds' do
      it 'is the triangle/noise/DMC table at twice its volume' do
        expect(described_class.mix(0, 0, 0, 1, 0)).to be_within(1e-12).of(163.67 / ((24_329.0 / 2) + 100))
      end
    end

    context 'when only the DMC sounds' do
      it 'is the triangle/noise/DMC table at its level' do
        expect(described_class.mix(0, 0, 0, 0, 1)).to be_within(1e-12).of(163.67 / ((24_329.0 / 1) + 100))
      end
    end

    context 'when the triangle, the noise and the DMC sound at their maxima' do
      it 'is the triangle/noise/DMC table at 202, within 0.5% of the exact formula', :aggregate_failures do
        output = described_class.mix(0, 0, 15, 15, 127)
        expect(output).to be_within(1e-12).of(163.67 / ((24_329.0 / 202) + 100))
        expect(output).to be_within(0.005 * output)
          .of(159.79 / ((1 / ((15 / 8227.0) + (15 / 12_241.0) + (127 / 22_638.0))) + 100))
      end
    end

    context 'when every channel sounds at its maximum' do
      it 'is the sum of both tables at their last entries' do
        expect(described_class.mix(15, 15, 15, 15, 127))
          .to be_within(1e-12).of((95.52 / ((8128.0 / 30) + 100)) + (163.67 / ((24_329.0 / 202) + 100)))
      end
    end
  end
end
