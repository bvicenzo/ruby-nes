# frozen_string_literal: true

RSpec.describe FlatBus do
  describe '#read' do
    subject(:bus) { described_class.new }

    context 'when the address is outside $0000-$FFFF' do
      context 'and it is negative' do
        it 'raises ArgumentError naming the address' do
          expect { bus.read(-1) }.to raise_error(ArgumentError, /address -\$0001/)
        end
      end

      context 'and it is $10000' do
        it 'raises ArgumentError naming the address' do
          expect { bus.read(0x10000) }.to raise_error(ArgumentError, /address \$10000/)
        end
      end
    end

    context 'when the address is inside $0000-$FFFF' do
      context 'and nothing was written there' do
        it 'returns $00' do
          expect(bus.read(0x1234)).to eq(0x00)
        end
      end

      context 'and a byte was written there' do
        before { bus.write(0xFFFF, 0x5A) }

        it 'returns that byte' do
          expect(bus.read(0xFFFF)).to eq(0x5A)
        end
      end
    end
  end

  describe '#write' do
    subject(:bus) { described_class.new }

    context 'when the address is outside $0000-$FFFF' do
      context 'and it is negative' do
        it 'raises ArgumentError naming the address' do
          expect { bus.write(-1, 0x5A) }.to raise_error(ArgumentError, /address -\$0001/)
        end
      end

      context 'and it is $10000' do
        it 'raises ArgumentError naming the address' do
          expect { bus.write(0x10000, 0x5A) }.to raise_error(ArgumentError, /address \$10000/)
        end
      end
    end

    context 'when the address is inside $0000-$FFFF' do
      context 'but the value is negative' do
        it 'raises ArgumentError naming the value' do
          expect { bus.write(0x0100, -1) }.to raise_error(ArgumentError, /value -\$01/)
        end
      end

      context 'but the value is $100' do
        it 'raises ArgumentError naming the value' do
          expect { bus.write(0x0100, 0x100) }.to raise_error(ArgumentError, /value \$100/)
        end
      end

      context 'and the value is a byte' do
        it 'keeps the byte at that address only', :aggregate_failures do
          bus.write(0x0100, 0xFF)

          expect(bus.read(0x0100)).to eq(0xFF)
          expect(bus.read(0x0101)).to eq(0x00)
        end
      end
    end
  end
end
