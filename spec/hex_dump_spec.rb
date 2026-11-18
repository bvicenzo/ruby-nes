# frozen_string_literal: true

RSpec.describe HexDump do
  describe '.bytes' do
    context 'when the dump is not whole bytes of hex digits' do
      context 'and it has an odd number of digits' do
        it 'raises ArgumentError' do
          expect { described_class.bytes('4E 45 5') }.to raise_error(ArgumentError, /4E 45 5/)
        end
      end

      context 'and it has a character that is not a hex digit' do
        it 'raises ArgumentError' do
          expect { described_class.bytes('4E 4G') }.to raise_error(ArgumentError, /4E 4G/)
        end
      end
    end

    context 'when the dump is whole bytes of hex digits' do
      context 'and they are separated by spaces' do
        it 'returns the binary string they spell' do
          expect(described_class.bytes('4E 45 53 1A')).to eq("NES\x1A".b)
        end
      end

      context 'and they span several lines' do
        it 'returns the binary string they spell' do
          expect(described_class.bytes("4E 45\n53 1A\n")).to eq("NES\x1A".b)
        end
      end
    end
  end
end
