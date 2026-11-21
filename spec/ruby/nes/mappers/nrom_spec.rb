# frozen_string_literal: true

RSpec.describe Ruby::Nes::Mappers::Nrom do
  describe '.new' do
    context 'when the PRG ROM is neither 16 nor 32 KiB' do
      let(:cartridge) { Cartridges.build(prg_rom: Array.new(49_152, 0xEA)) }

      it 'raises InvalidCartridge naming the PRG ROM size' do
        expect { described_class.new(cartridge) }
          .to raise_error(Ruby::Nes::Mappers::InvalidCartridge, /PRG ROM of 49152 bytes/)
      end
    end

    context 'when the PRG ROM is 16 or 32 KiB' do
      context 'but the CHR ROM is neither 8 KiB nor absent' do
        let(:cartridge) { Cartridges.build(chr_rom: Array.new(16_384, 0x00)) }

        it 'raises InvalidCartridge naming the CHR ROM size' do
          expect { described_class.new(cartridge) }
            .to raise_error(Ruby::Nes::Mappers::InvalidCartridge, /CHR ROM of 16384 bytes/)
        end
      end

      context 'and the board has CHR RAM' do
        let(:cartridge) { Cartridges.build(chr_rom: []) }

        it 'builds the board' do
          expect { described_class.new(cartridge) }.not_to raise_error
        end
      end

      context 'and the CHR ROM is 8 KiB' do
        let(:cartridge) { Cartridges.build(prg_rom: Array.new(32_768, 0xEA)) }

        it 'builds the board' do
          expect { described_class.new(cartridge) }.not_to raise_error
        end
      end
    end
  end

  describe '#cpu_write' do
    subject(:nrom) { described_class.new(Cartridges.build) }

    context 'when the address is in PRG RAM' do
      before { nrom.cpu_write(0x6000, 0x77) }

      it 'is read back at the same address' do
        expect(nrom.cpu_read(0x6000, 0x5A)).to eq(0x77)
      end
    end
  end
end
