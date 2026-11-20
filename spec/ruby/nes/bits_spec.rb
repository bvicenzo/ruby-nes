# frozen_string_literal: true

RSpec.describe Ruby::Nes::Bits do
  describe '.wrap_to_byte' do
    context 'when the value fits in a byte' do
      it 'returns the value' do
        expect(described_class.wrap_to_byte(0xFF)).to eq(0xFF)
      end
    end

    context 'when the value is one past a byte' do
      it 'wraps to zero' do
        expect(described_class.wrap_to_byte(0x100)).to eq(0x00)
      end
    end

    context 'when the value is below zero' do
      it 'wraps from the top of the byte' do
        expect(described_class.wrap_to_byte(-3)).to eq(0xFD)
      end
    end
  end

  describe '.wrap_to_word' do
    context 'when the value fits in a word' do
      it 'returns the value' do
        expect(described_class.wrap_to_word(0xFFFF)).to eq(0xFFFF)
      end
    end

    context 'when the value is one past a word' do
      it 'wraps to zero' do
        expect(described_class.wrap_to_word(0x10000)).to eq(0x0000)
      end
    end

    context 'when the value is below zero' do
      it 'wraps from the top of the word' do
        expect(described_class.wrap_to_word(-3)).to eq(0xFFFD)
      end
    end
  end

  describe '.high_nibble' do
    context 'when the low half is clear' do
      it 'returns the high half' do
        expect(described_class.high_nibble(0x40)).to eq(0x4)
      end
    end

    context 'when the low half is set' do
      it 'returns the high half' do
        expect(described_class.high_nibble(0x4F)).to eq(0x4)
      end
    end

    context 'when the high half is all ones' do
      it 'returns fifteen' do
        expect(described_class.high_nibble(0xFF)).to eq(0xF)
      end
    end
  end

  describe '.combine_nibbles' do
    context 'when both halves are non-zero' do
      it 'places the high half above the low half' do
        expect(described_class.combine_nibbles(low: 0x1, high: 0x2)).to eq(0x21)
      end
    end

    context 'when the high half is zero' do
      it 'returns the low half' do
        expect(described_class.combine_nibbles(low: 0x4, high: 0x0)).to eq(0x04)
      end
    end

    context 'when both halves are all ones' do
      it 'returns a full byte' do
        expect(described_class.combine_nibbles(low: 0xF, high: 0xF)).to eq(0xFF)
      end
    end
  end

  describe '.set_flag' do
    context 'when the flag is clear' do
      it 'turns it on, leaving the other bits' do
        expect(described_class.set_flag(0b0010_0001, 0b1000_0000)).to eq(0b1010_0001)
      end
    end

    context 'when the flag is already set' do
      it 'leaves the value as it is' do
        expect(described_class.set_flag(0b1010_0001, 0b1000_0000)).to eq(0b1010_0001)
      end
    end
  end

  describe '.clear_flag' do
    context 'when the flag is set' do
      it 'turns it off, leaving the other bits' do
        expect(described_class.clear_flag(0b1010_0001, 0b1000_0000)).to eq(0b0010_0001)
      end
    end

    context 'when the flag is already clear' do
      it 'leaves the value as it is' do
        expect(described_class.clear_flag(0b0010_0001, 0b1000_0000)).to eq(0b0010_0001)
      end
    end
  end

  describe '.combine_bytes' do
    it 'places the high byte above the low byte' do
      expect(described_class.combine_bytes(low: 0x16, high: 0x80)).to eq(0x8016)
    end
  end
end
