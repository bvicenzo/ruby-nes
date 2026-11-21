# frozen_string_literal: true

# The MMC1's serial load port (https://www.nesdev.org/wiki/MMC1): "On the first four writes, the MMC1 shifts bit 0 into
# a shift register. On the fifth write, the MMC1 copies bit 0 and the shift register contents into an internal
# register", the first write's bit landing in bit 0; "After the fifth write, the shift register is cleared
# automatically". "When the serial port is written to on consecutive cycles, it ignores every write after the first":
# a write less than 2 cycles after the previous one is ignored, and every write, ignored or reset, becomes the previous
# one (plan 20, decision 2). "the bit 7 reset is never ignored". Accepted writes here are 4 cycles apart, as two
# `STA` instructions at least are.
RSpec.describe Ruby::Nes::Mappers::Mmc1::SerialPort do
  describe '#shift' do
    subject(:serial_port) { described_class.new }

    context 'when the write comes less than 2 cycles after the previous one' do
      context 'and the previous one was on the same cycle' do
        # Bits 1, 0, 1 and 1 so far: the fifth write completes $0D with a 0, $1D with a 1.
        before do
          serial_port.shift(1, 10)
          serial_port.shift(0, 14)
          serial_port.shift(1, 18)
          serial_port.shift(1, 22)
        end

        it 'ignores the write', :aggregate_failures do
          expect(serial_port.shift(1, 22)).to be_nil
          expect(serial_port.shift(0, 26)).to eq(0b01101)
        end
      end

      context 'and the previous one was 1 cycle before' do
        before do
          serial_port.shift(1, 10)
          serial_port.shift(0, 14)
          serial_port.shift(1, 18)
          serial_port.shift(1, 22)
        end

        it 'ignores the write', :aggregate_failures do
          expect(serial_port.shift(1, 23)).to be_nil
          expect(serial_port.shift(0, 27)).to eq(0b01101)
        end
      end

      context 'and the previous one was itself ignored' do
        # The fourth write is at cycle 21 and the ignored one at 22: cycle 23 is 2 cycles after the last accepted write
        # but 1 after the ignored one.
        before do
          serial_port.shift(1, 10)
          serial_port.shift(0, 14)
          serial_port.shift(1, 18)
          serial_port.shift(1, 21)
          serial_port.shift(1, 22)
        end

        it 'ignores the write', :aggregate_failures do
          expect(serial_port.shift(1, 23)).to be_nil
          expect(serial_port.shift(0, 27)).to eq(0b01101)
        end
      end

      context 'and the previous one was a reset' do
        # Bill & Ted's INC on a $FF byte: the $FF resets, the $00 on the next cycle must be ignored.
        before { serial_port.reset(10) }

        it 'ignores the write', :aggregate_failures do
          expect(serial_port.shift(1, 10)).to be_nil
          expect(serial_port.shift(0, 14)).to be_nil
          expect(serial_port.shift(0, 18)).to be_nil
          expect(serial_port.shift(0, 22)).to be_nil
          expect(serial_port.shift(0, 26)).to be_nil
          expect(serial_port.shift(0, 30)).to eq(0)
        end
      end
    end

    context 'when the write comes 2 or more cycles after the previous one' do
      context 'and it is one of the first four' do
        it 'returns nothing', :aggregate_failures do
          expect(serial_port.shift(1, 10)).to be_nil
          expect(serial_port.shift(0, 14)).to be_nil
          expect(serial_port.shift(1, 18)).to be_nil
          expect(serial_port.shift(1, 22)).to be_nil
        end
      end

      context 'and it is the fifth' do
        before do
          serial_port.shift(1, 10)
          serial_port.shift(0, 14)
          serial_port.shift(1, 18)
          serial_port.shift(1, 22)
        end

        it 'returns the five bit 0s, low bit first' do
          expect(serial_port.shift(1, 26)).to eq(0b11101)
        end
      end

      context 'and the writes carry bits other than bit 0' do
        # Bit 0 of $7E is 0 and of $7F is 1: bits 0, 1, 0 and 1 so far.
        before do
          serial_port.shift(0x7E, 10)
          serial_port.shift(0x7F, 14)
          serial_port.shift(0x7E, 18)
          serial_port.shift(0x7F, 22)
        end

        it 'returns only their bit 0s' do
          expect(serial_port.shift(0x7F, 26)).to eq(0b11010)
        end
      end

      context 'and a value was completed before' do
        # Five 1s complete $1F; then four 0s.
        before do
          serial_port.shift(1, 10)
          serial_port.shift(1, 14)
          serial_port.shift(1, 18)
          serial_port.shift(1, 22)
          serial_port.shift(1, 26)
          serial_port.shift(0, 30)
          serial_port.shift(0, 34)
          serial_port.shift(0, 38)
          serial_port.shift(0, 42)
        end

        it 'returns a value without the earlier bits' do
          expect(serial_port.shift(0, 46)).to eq(0)
        end
      end

      context 'and it comes exactly 2 cycles after' do
        before do
          serial_port.shift(1, 10)
          serial_port.shift(0, 14)
          serial_port.shift(1, 18)
          serial_port.shift(1, 22)
        end

        it 'counts toward the five' do
          expect(serial_port.shift(1, 24)).to eq(0b11101)
        end
      end
    end

    context 'when there is no previous write' do
      # The first write, at cycle 0, is the one under test; the next three are 4 cycles apart.
      before do
        serial_port.shift(1, 0)
        serial_port.shift(0, 4)
        serial_port.shift(1, 8)
        serial_port.shift(1, 12)
      end

      it 'counts toward the five' do
        expect(serial_port.shift(1, 16)).to eq(0b11101)
      end
    end
  end

  describe '#reset' do
    subject(:serial_port) { described_class.new }

    context 'when bits were shifted before' do
      before do
        serial_port.shift(1, 10)
        serial_port.shift(1, 14)
      end

      it 'discards them', :aggregate_failures do
        serial_port.reset(18)
        expect(serial_port.shift(0, 22)).to be_nil
        expect(serial_port.shift(0, 26)).to be_nil
        expect(serial_port.shift(0, 30)).to be_nil
        expect(serial_port.shift(0, 34)).to be_nil
        expect(serial_port.shift(0, 38)).to eq(0)
      end
    end

    context 'when it comes on the same cycle as a shift' do
      # Shinsenden sets bit 7 on the second write of RRA abs,X: "the bit 7 reset is never ignored".
      before do
        serial_port.shift(1, 10)
        serial_port.shift(1, 14)
      end

      it 'still discards the bits', :aggregate_failures do
        serial_port.reset(14)
        expect(serial_port.shift(0, 18)).to be_nil
        expect(serial_port.shift(0, 22)).to be_nil
        expect(serial_port.shift(0, 26)).to be_nil
        expect(serial_port.shift(0, 30)).to be_nil
        expect(serial_port.shift(0, 34)).to eq(0)
      end
    end
  end
end
