# frozen_string_literal: true

RSpec.describe Ruby::Nes::Mappers::Uxrom do
  describe '#cpu_read' do
    subject(:uxrom) { described_class.new(cartridge) }

    # 128 KiB, eight 16 KiB banks; the last byte of each holds its number.
    let(:cartridge) { Cartridges.build(prg_rom: Array.new(8) { |bank| [*Array.new(16_383, 0xFF), bank] }.flatten) }

    context 'when the address is in the PRG RAM range' do
      it 'returns the data bus value' do
        expect(uxrom.cpu_read(0x6000, 0x5A)).to eq(0x5A)
      end
    end

    context 'when the address is in PRG ROM' do
      context 'and it is in the switchable window' do
        it 'returns the first bank' do
          expect(uxrom.cpu_read(0xBFFF, 0x5A)).to eq(0)
        end
      end

      context 'and it is in the fixed window' do
        it 'returns the last bank' do
          expect(uxrom.cpu_read(0xFFFF, 0x5A)).to eq(7)
        end
      end
    end
  end

  describe '#cpu_write' do
    subject(:uxrom) { described_class.new(cartridge) }

    # 128 KiB, eight 16 KiB banks; the last byte of each holds its number, every other byte is $FF.
    let(:cartridge) { Cartridges.build(prg_rom: Array.new(8) { |bank| [*Array.new(16_383, 0xFF), bank] }.flatten) }

    context 'when the address is in PRG ROM' do
      context 'and the bank exceeds the PRG ROM' do
        before { uxrom.cpu_write(0x8000, 10) }

        it 'shows the bank wrapped by the PRG ROM size at $8000' do
          expect(uxrom.cpu_read(0xBFFF, 0x5A)).to eq(2)
        end
      end

      context 'and the bank is in the PRG ROM' do
        context 'and the address is $8000' do
          before { uxrom.cpu_write(0x8000, 3) }

          it 'shows that bank at $8000' do
            expect(uxrom.cpu_read(0xBFFF, 0x5A)).to eq(3)
          end

          it 'keeps the last bank at $C000' do
            expect(uxrom.cpu_read(0xFFFF, 0x5A)).to eq(7)
          end
        end

        context 'and the address is $FFFF' do
          before { uxrom.cpu_write(0xFFFF, 3) }

          it 'shows that bank at $8000' do
            expect(uxrom.cpu_read(0xBFFF, 0x5A)).to eq(3)
          end
        end

        context 'and the ROM byte at the address clears bits of the value' do
          # $BFFF holds bank 0's number, $00: ANDed with it, any bank would become 0.
          before { uxrom.cpu_write(0xBFFF, 3) }

          it 'selects the bank written' do
            expect(uxrom.cpu_read(0xBFFF, 0x5A)).to eq(3)
          end
        end
      end
    end
  end
end
