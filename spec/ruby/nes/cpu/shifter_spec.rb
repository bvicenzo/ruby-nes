# frozen_string_literal: true

# Shifts and rotates (https://www.nesdev.org/wiki/Instruction_reference): ASL and ROL move every bit up and C takes the
# old bit 7; LSR and ROR move every bit down and C takes the old bit 0. ROL and ROR shift the old C into the bit left
# empty (bit 0 and bit 7); ASL and LSR shift in a 0, so LSR always clears N. Z and N come from the result.
RSpec.describe Ruby::Nes::Cpu::Shifter do
  describe '#shift_left' do
    subject(:shifter) { described_class.new(status:) }

    let(:status) { Ruby::Nes::Cpu::Status.new }

    context 'when the value is $40 and the carry is set' do
      before { status.restore(0x01) }

      it 'returns $80' do
        expect(shifter.shift_left(0x40)).to eq(0x80)
      end

      it 'clears carry and sets negative', :aggregate_failures do
        shifter.shift_left(0x40)
        expect(status).not_to be_carry
        expect(status).to be_negative
      end
    end

    context 'when the value is $80' do
      it 'returns $00' do
        expect(shifter.shift_left(0x80)).to eq(0x00)
      end

      it 'sets carry and zero', :aggregate_failures do
        shifter.shift_left(0x80)
        expect(status).to be_carry
        expect(status).to be_zero
      end
    end

    context 'when interrupt disable, decimal and overflow are set' do
      before { status.restore(0x4C) }

      it 'leaves them set' do
        shifter.shift_left(0x10)
        expect(status.byte_pushed_by_interrupt).to eq(0x6C)
      end
    end
  end

  describe '#shift_right' do
    subject(:shifter) { described_class.new(status:) }

    let(:status) { Ruby::Nes::Cpu::Status.new }

    context 'when the value is $02 and carry and negative are set' do
      before { status.restore(0x81) }

      it 'returns $01' do
        expect(shifter.shift_right(0x02)).to eq(0x01)
      end

      it 'clears carry, zero and negative', :aggregate_failures do
        shifter.shift_right(0x02)
        expect(status).not_to be_carry
        expect(status).not_to be_zero
        expect(status).not_to be_negative
      end
    end

    context 'when the value is $01' do
      it 'returns $00' do
        expect(shifter.shift_right(0x01)).to eq(0x00)
      end

      it 'sets carry and zero', :aggregate_failures do
        shifter.shift_right(0x01)
        expect(status).to be_carry
        expect(status).to be_zero
      end
    end

    context 'when interrupt disable, decimal and overflow are set' do
      before { status.restore(0x4C) }

      it 'leaves them set' do
        shifter.shift_right(0x10)
        expect(status.byte_pushed_by_interrupt).to eq(0x6C)
      end
    end
  end

  describe '#rotate_left' do
    subject(:shifter) { described_class.new(status:) }

    let(:status) { Ruby::Nes::Cpu::Status.new }

    context 'when the value is $40 and the carry is clear' do
      it 'returns $80' do
        expect(shifter.rotate_left(0x40)).to eq(0x80)
      end

      it 'clears carry and sets negative', :aggregate_failures do
        shifter.rotate_left(0x40)
        expect(status).not_to be_carry
        expect(status).to be_negative
      end
    end

    context 'when the value is $80 and the carry is set' do
      before { status.restore(0x01) }

      it 'returns $01' do
        expect(shifter.rotate_left(0x80)).to eq(0x01)
      end

      it 'sets carry and clears zero', :aggregate_failures do
        shifter.rotate_left(0x80)
        expect(status).to be_carry
        expect(status).not_to be_zero
      end
    end

    context 'when the value is $80 and the carry is clear' do
      it 'returns $00' do
        expect(shifter.rotate_left(0x80)).to eq(0x00)
      end

      it 'sets carry and zero', :aggregate_failures do
        shifter.rotate_left(0x80)
        expect(status).to be_carry
        expect(status).to be_zero
      end
    end

    context 'when interrupt disable, decimal and overflow are set' do
      before { status.restore(0x4C) }

      it 'leaves them set' do
        shifter.rotate_left(0x10)
        expect(status.byte_pushed_by_interrupt).to eq(0x6C)
      end
    end
  end

  describe '#rotate_right' do
    subject(:shifter) { described_class.new(status:) }

    let(:status) { Ruby::Nes::Cpu::Status.new }

    context 'when the value is $02 and the carry is clear' do
      before { status.restore(0x80) }

      it 'returns $01' do
        expect(shifter.rotate_right(0x02)).to eq(0x01)
      end

      it 'clears carry and negative', :aggregate_failures do
        shifter.rotate_right(0x02)
        expect(status).not_to be_carry
        expect(status).not_to be_negative
      end
    end

    context 'when the value is $01 and the carry is set' do
      before { status.restore(0x01) }

      it 'returns $80' do
        expect(shifter.rotate_right(0x01)).to eq(0x80)
      end

      it 'sets carry and negative', :aggregate_failures do
        shifter.rotate_right(0x01)
        expect(status).to be_carry
        expect(status).to be_negative
      end
    end

    context 'when the value is $01 and the carry is clear' do
      it 'returns $00' do
        expect(shifter.rotate_right(0x01)).to eq(0x00)
      end

      it 'sets carry and zero', :aggregate_failures do
        shifter.rotate_right(0x01)
        expect(status).to be_carry
        expect(status).to be_zero
      end
    end

    context 'when interrupt disable, decimal and overflow are set' do
      before { status.restore(0x4C) }

      it 'leaves them set' do
        shifter.rotate_right(0x10)
        expect(status.byte_pushed_by_interrupt).to eq(0x6C)
      end
    end
  end
end
