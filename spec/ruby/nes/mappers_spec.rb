# frozen_string_literal: true

RSpec.describe Ruby::Nes::Mappers do
  describe '.build' do
    context 'when the cartridge has no PRG ROM' do
      let(:cartridge) { Cartridges.build(prg_rom: []) }

      it 'raises InvalidCartridge' do
        expect { described_class.build(cartridge) }
          .to raise_error(Ruby::Nes::Mappers::InvalidCartridge, /no PRG ROM/)
      end
    end

    context 'when the cartridge has PRG ROM' do
      context 'but its mapper is not supported' do
        let(:cartridge) { Cartridges.build(mapper_number: 5) }

        it 'raises UnsupportedMapper naming the number' do
          expect { described_class.build(cartridge) }
            .to raise_error(Ruby::Nes::Mappers::UnsupportedMapper, /mapper 5\b/)
        end
      end

      context 'and its mapper is 0' do
        let(:cartridge) { Cartridges.build(mirroring: :vertical, mapper_number: 0) }

        it 'returns an NROM board built from the cartridge' do
          expect(described_class.build(cartridge))
            .to be_a(Ruby::Nes::Mappers::Nrom).and have_attributes(mirroring: :vertical)
        end
      end

      context 'and its mapper is 1' do
        let(:cartridge) { Cartridges.build(mapper_number: 1) }

        it 'returns an MMC1 board built from the cartridge' do
          expect(described_class.build(cartridge)).to be_a(Ruby::Nes::Mappers::Mmc1)
        end
      end

      context 'and its mapper is 2' do
        let(:cartridge) { Cartridges.build(mirroring: :vertical, mapper_number: 2) }

        it 'returns a UxROM board built from the cartridge' do
          expect(described_class.build(cartridge))
            .to be_a(Ruby::Nes::Mappers::Uxrom).and have_attributes(mirroring: :vertical)
        end
      end

      context 'and its mapper is 3' do
        let(:cartridge) { Cartridges.build(mirroring: :vertical, mapper_number: 3) }

        it 'returns a CNROM board built from the cartridge' do
          expect(described_class.build(cartridge))
            .to be_a(Ruby::Nes::Mappers::Cnrom).and have_attributes(mirroring: :vertical)
        end
      end

      context 'and its mapper is 4' do
        let(:cartridge) { Cartridges.build(prg_rom: Array.new(262_144, 0xEA), mapper_number: 4) }

        it 'returns an MMC3 board built from the cartridge' do
          expect(described_class.build(cartridge)).to be_a(Ruby::Nes::Mappers::Mmc3)
        end
      end

      context 'and its mapper is 7' do
        let(:cartridge) { Cartridges.build(prg_rom: Array.new(32_768, 0xEA), mapper_number: 7) }

        it 'returns an AxROM board built from the cartridge' do
          expect(described_class.build(cartridge)).to be_a(Ruby::Nes::Mappers::Axrom)
        end
      end
    end
  end
end
