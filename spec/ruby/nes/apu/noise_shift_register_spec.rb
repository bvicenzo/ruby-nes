# frozen_string_literal: true

# The noise channel's 15-bit shift register (https://www.nesdev.org/wiki/APU_Noise). "On power-up, the shift register
# is loaded with the value 1" (plan 23, decision 6). When clocked, "Feedback is calculated as the exclusive-OR of bit 0
# and one other bit: bit 6 if periodic noise mode (M bit) is set, otherwise bit 1"; "The shift register is shifted
# right by one bit"; "Bit 14, the leftmost bit, is set to the feedback calculated earlier". The channel is muted "when
# bit 0 of the shift register is set". The values below are picked so that the other mode's bit would feed the
# opposite bit into bit 14.
RSpec.describe Ruby::Nes::Apu::NoiseShiftRegister do
  describe '.new' do
    context 'when the console powers up' do
      it 'holds 1' do
        expect(described_class.new.value).to eq(0x0001)
      end
    end
  end

  describe '#periodic=' do
    context 'when periodic mode is turned off after being on' do
      subject(:shift_register) { described_class.new(value: 0x0041).tap { |register| register.periodic = true } }

      it 'taps bit 1 again' do
        shift_register.periodic = false
        shift_register.step
        expect(shift_register.value).to eq(0x4020)
      end
    end
  end

  describe '#step' do
    context 'when periodic mode is off' do
      context 'and bits 0 and 1 differ' do
        subject(:shift_register) { described_class.new(value: 0x0041) }

        it 'shifts right and feeds 1 into bit 14' do
          shift_register.step
          expect(shift_register.value).to eq(0x4020)
        end
      end

      context 'and bits 0 and 1 are equal' do
        subject(:shift_register) { described_class.new(value: 0x0003) }

        it 'shifts right and feeds 0 into bit 14' do
          shift_register.step
          expect(shift_register.value).to eq(0x0001)
        end
      end
    end

    context 'when periodic mode is on' do
      context 'and bits 0 and 6 differ' do
        subject(:shift_register) { described_class.new(value: 0x0003).tap { |register| register.periodic = true } }

        it 'shifts right and feeds 1 into bit 14' do
          shift_register.step
          expect(shift_register.value).to eq(0x4001)
        end
      end

      context 'and bits 0 and 6 are equal' do
        subject(:shift_register) { described_class.new(value: 0x0041).tap { |register| register.periodic = true } }

        it 'shifts right and feeds 0 into bit 14' do
          shift_register.step
          expect(shift_register.value).to eq(0x0020)
        end
      end
    end
  end

  describe '#muting?' do
    context 'when bit 0 is set' do
      subject(:shift_register) { described_class.new(value: 0x0001) }

      it { is_expected.to be_muting }
    end

    context 'when bit 0 is clear' do
      subject(:shift_register) { described_class.new(value: 0x4000) }

      it { is_expected.not_to be_muting }
    end
  end
end
