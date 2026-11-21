# frozen_string_literal: true

# The noise channel's length counter (https://www.nesdev.org/wiki/APU_Length_Counter), all plan 22 brings of it so that
# $4015 and apu_test's length counter tests see the four main channels (plan 22, decision 8; the rest is plan 23's,
# https://www.nesdev.org/wiki/APU_Noise). Its registers are numbered 0-3 from its first address ($400C-$400F): the halt
# flag is bit 5 of $400C, and a write to $400F loads the counter. Half frames clock it, $4015 enables it.
RSpec.describe Ruby::Nes::Apu::Noise do
  describe '#write' do
    context 'when the register is the first' do
      context 'and the halt flag is set' do
        subject(:channel) { described_class.new(length_counter:) }

        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, :halted= => nil) }

        it 'halts the length counter' do
          channel.write(0, 0x3F)
          expect(length_counter).to have_received(:halted=).with(true)
        end
      end

      context 'and the halt flag is clear' do
        subject(:channel) { described_class.new(length_counter:) }

        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, :halted= => nil) }

        it 'lets the length counter run' do
          channel.write(0, 0x1F)
          expect(length_counter).to have_received(:halted=).with(false)
        end
      end
    end

    context 'when the register is the second or the third' do
      subject(:channel) { described_class.new(length_counter:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter) }

      it 'leaves the length counter' do
        expect { channel.write(2, 0xFF) }.not_to raise_error
      end
    end

    context 'when the register is the fourth' do
      subject(:channel) { described_class.new(length_counter:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, load: nil) }

      it 'loads the length counter' do
        channel.write(3, 0xFA)
        expect(length_counter).to have_received(:load).with(0xFA)
      end
    end
  end

  describe '#half_frame' do
    context 'when the frame counter clocks it' do
      subject(:channel) { described_class.new(length_counter:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, clock: nil) }

      it 'clocks the length counter' do
        channel.half_frame
        expect(length_counter).to have_received(:clock)
      end
    end
  end

  describe '#enabled=' do
    context 'when $4015 disables the channel' do
      subject(:channel) { described_class.new(length_counter:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, :enabled= => nil) }

      it 'disables the length counter' do
        channel.enabled = false
        expect(length_counter).to have_received(:enabled=).with(false)
      end
    end
  end

  describe '#active?' do
    context 'when the length counter is above 0' do
      subject(:channel) { described_class.new(length_counter:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }

      it { is_expected.to be_active }
    end
  end
end
