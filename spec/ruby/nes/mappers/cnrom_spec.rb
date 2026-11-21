# frozen_string_literal: true

RSpec.describe Ruby::Nes::Mappers::Cnrom do
  describe '.new' do
    context 'when the PRG ROM is neither 16 nor 32 KiB' do
      let(:cartridge) { Cartridges.build(prg_rom: Array.new(65_536, 0xFF)) }

      it 'raises InvalidCartridge naming the PRG ROM size' do
        expect { described_class.new(cartridge) }
          .to raise_error(Ruby::Nes::Mappers::InvalidCartridge, /PRG ROM of 65536 bytes/)
      end
    end

    context 'when the PRG ROM is 16 or 32 KiB' do
      let(:cartridge) { Cartridges.build(prg_rom: Array.new(32_768, 0xFF)) }

      it 'builds the board' do
        expect { described_class.new(cartridge) }.not_to raise_error
      end
    end
  end

  describe '#cpu_read' do
    subject(:cnrom) { described_class.new(Cartridges.build) }

    context 'when the address is in the PRG RAM range' do
      it 'returns the data bus value' do
        expect(cnrom.cpu_read(0x6000, 0x5A)).to eq(0x5A)
      end
    end
  end

  describe '#ppu_read' do
    subject(:cnrom) { described_class.new(cartridge) }

    # 32 KiB of CHR ROM in numbered 4 KiB halves: the 8 KiB bank n shows half 2n at $0000 and 2n + 1 at $1000.
    let(:cartridge) { Cartridges.build(chr_rom: Cartridges.numbered_banks(count: 8, size: 4_096)) }

    context 'when no bank was selected yet' do
      it 'returns the first CHR bank', :aggregate_failures do
        expect(cnrom.ppu_read(0x0000)).to eq(0)
        expect(cnrom.ppu_read(0x1000)).to eq(1)
      end
    end
  end

  describe '#cpu_write' do
    subject(:cnrom) { described_class.new(cartridge) }

    # 32 KiB of PRG ROM, all $FF but $01 at $9000; 32 KiB of CHR ROM in numbered 4 KiB halves: the 8 KiB bank n shows
    # half 2n at $0000 and 2n + 1 at $1000.
    let(:cartridge) do
      Cartridges.build(
        prg_rom: [*Array.new(4_096, 0xFF), 0x01, *Array.new(28_671, 0xFF)],
        chr_rom: Cartridges.numbered_banks(count: 8, size: 4_096)
      )
    end

    context 'when the address is in PRG ROM' do
      context 'and the ROM byte at the address clears bits of the value' do
        # $03 written where the ROM holds $01: the board sees $03 AND $01.
        before { cnrom.cpu_write(0x9000, 0x03) }

        it 'selects the bank the two have in common' do
          expect(cnrom.ppu_read(0x0000)).to eq(2)
        end
      end

      context 'and the ROM byte at the address keeps every bit of the value' do
        context 'and the bank exceeds the CHR ROM' do
          # $13: bank 3 with bit 4, a security diode output, set.
          before { cnrom.cpu_write(0x8000, 0x13) }

          it 'selects the bank wrapped by the CHR ROM size' do
            expect(cnrom.ppu_read(0x0000)).to eq(6)
          end
        end

        context 'and the bank is in the CHR ROM' do
          context 'and the address is $8000' do
            before { cnrom.cpu_write(0x8000, 2) }

            it 'shows that bank in both pattern tables', :aggregate_failures do
              expect(cnrom.ppu_read(0x0000)).to eq(4)
              expect(cnrom.ppu_read(0x1000)).to eq(5)
            end
          end

          context 'and the address is $FFFF' do
            before { cnrom.cpu_write(0xFFFF, 2) }

            it 'shows that bank in the pattern tables' do
              expect(cnrom.ppu_read(0x0000)).to eq(4)
            end
          end
        end
      end
    end
  end
end
