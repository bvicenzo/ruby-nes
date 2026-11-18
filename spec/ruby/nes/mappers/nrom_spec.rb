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

  describe '#cpu_read' do
    subject(:nrom) { described_class.new(cartridge) }

    context 'when the address is below PRG RAM' do
      let(:cartridge) { Cartridges.build }

      context 'and it is $4020' do
        it 'returns the data bus value' do
          expect(nrom.cpu_read(0x4020, 0x5A)).to eq(0x5A)
        end
      end

      context 'and it is $5FFF' do
        it 'returns the data bus value' do
          expect(nrom.cpu_read(0x5FFF, 0x5A)).to eq(0x5A)
        end
      end
    end

    context 'when the address is in PRG RAM' do
      let(:cartridge) { Cartridges.build }

      it 'returns zero before anything is written' do
        expect(nrom.cpu_read(0x6000, 0x5A)).to eq(0x00)
      end
    end

    context 'when the address is in PRG ROM' do
      context 'and the board is NROM-128' do
        let(:cartridge) { Cartridges.build(prg_rom: [0x11, *Array.new(16_382, 0xEA), 0x22]) }

        context 'and the address is $8000' do
          it 'returns the first PRG ROM byte' do
            expect(nrom.cpu_read(0x8000, 0x5A)).to eq(0x11)
          end
        end

        context 'and the address is $BFFF' do
          it 'returns the last PRG ROM byte' do
            expect(nrom.cpu_read(0xBFFF, 0x5A)).to eq(0x22)
          end
        end

        context 'and the address is $C000' do
          it 'returns the first PRG ROM byte' do
            expect(nrom.cpu_read(0xC000, 0x5A)).to eq(0x11)
          end
        end

        context 'and the address is $FFFF' do
          it 'returns the last PRG ROM byte' do
            expect(nrom.cpu_read(0xFFFF, 0x5A)).to eq(0x22)
          end
        end
      end

      context 'and the board is NROM-256' do
        let(:cartridge) do
          Cartridges.build(prg_rom: [0x11, *Array.new(16_382, 0xEA), 0x22, 0x33, *Array.new(16_382, 0xEA), 0x44])
        end

        context 'and the address is $8000' do
          it 'returns the first PRG ROM byte' do
            expect(nrom.cpu_read(0x8000, 0x5A)).to eq(0x11)
          end
        end

        context 'and the address is $BFFF' do
          it 'returns the last byte of the first half' do
            expect(nrom.cpu_read(0xBFFF, 0x5A)).to eq(0x22)
          end
        end

        context 'and the address is $C000' do
          it 'returns the first byte of the second half' do
            expect(nrom.cpu_read(0xC000, 0x5A)).to eq(0x33)
          end
        end

        context 'and the address is $FFFF' do
          it 'returns the last PRG ROM byte' do
            expect(nrom.cpu_read(0xFFFF, 0x5A)).to eq(0x44)
          end
        end
      end
    end
  end

  describe '#cpu_write' do
    subject(:nrom) { described_class.new(cartridge) }

    context 'when the address is below PRG RAM' do
      let(:cartridge) { Cartridges.build }

      before { nrom.cpu_write(0x5FFF, 0x77) }

      it 'keeps reading the data bus value there' do
        expect(nrom.cpu_read(0x5FFF, 0x5A)).to eq(0x5A)
      end

      it 'leaves PRG RAM unchanged' do
        expect(nrom.cpu_read(0x7FFF, 0x5A)).to eq(0x00)
      end
    end

    context 'when the address is in PRG RAM' do
      let(:cartridge) { Cartridges.build }

      context 'and it is $6000' do
        before { nrom.cpu_write(0x6000, 0x77) }

        it 'is read back at the same address' do
          expect(nrom.cpu_read(0x6000, 0x5A)).to eq(0x77)
        end
      end

      context 'and it is $7FFF' do
        before { nrom.cpu_write(0x7FFF, 0x77) }

        it 'is read back at the same address' do
          expect(nrom.cpu_read(0x7FFF, 0x5A)).to eq(0x77)
        end
      end
    end

    context 'when the address is in PRG ROM' do
      let(:cartridge) { Cartridges.build(prg_rom: [0x11, *Array.new(16_382, 0xEA), 0x22]) }

      before { nrom.cpu_write(0x8000, 0x77) }

      it 'leaves the PRG ROM byte unchanged' do
        expect(nrom.cpu_read(0x8000, 0x5A)).to eq(0x11)
      end

      it 'leaves PRG RAM unchanged' do
        expect(nrom.cpu_read(0x6000, 0x5A)).to eq(0x00)
      end
    end
  end

  describe '#ppu_read' do
    subject(:nrom) { described_class.new(cartridge) }

    context 'when the board has CHR ROM' do
      let(:cartridge) { Cartridges.build(chr_rom: [0x33, *Array.new(8_190, 0xEA), 0x44]) }

      context 'and the address is $0000' do
        it 'returns the first CHR ROM byte' do
          expect(nrom.ppu_read(0x0000)).to eq(0x33)
        end
      end

      context 'and the address is $1FFF' do
        it 'returns the last CHR ROM byte' do
          expect(nrom.ppu_read(0x1FFF)).to eq(0x44)
        end
      end
    end

    context 'when the board has CHR RAM' do
      let(:cartridge) { Cartridges.build(chr_rom: []) }

      it 'returns zero before anything is written' do
        expect(nrom.ppu_read(0x1FFF)).to eq(0x00)
      end
    end
  end

  describe '#ppu_write' do
    subject(:nrom) { described_class.new(cartridge) }

    context 'when the board has CHR ROM' do
      let(:cartridge) { Cartridges.build(chr_rom: [0x33, *Array.new(8_190, 0xEA), 0x44]) }

      before { nrom.ppu_write(0x0000, 0x77) }

      it 'leaves the CHR ROM byte unchanged' do
        expect(nrom.ppu_read(0x0000)).to eq(0x33)
      end
    end

    context 'when the board has CHR RAM' do
      let(:cartridge) { Cartridges.build(chr_rom: []) }

      context 'and the address is $0000' do
        before { nrom.ppu_write(0x0000, 0x77) }

        it 'is read back at the same address' do
          expect(nrom.ppu_read(0x0000)).to eq(0x77)
        end
      end

      context 'and the address is $1FFF' do
        before { nrom.ppu_write(0x1FFF, 0x77) }

        it 'is read back at the same address' do
          expect(nrom.ppu_read(0x1FFF)).to eq(0x77)
        end
      end
    end
  end

  describe '#mirroring' do
    subject(:nrom) { described_class.new(cartridge) }

    context 'when the header says horizontal' do
      let(:cartridge) { Cartridges.build(mirroring: :horizontal) }

      it 'is horizontal' do
        expect(nrom.mirroring).to eq(:horizontal)
      end
    end

    context 'when the header says vertical' do
      let(:cartridge) { Cartridges.build(mirroring: :vertical) }

      it 'is vertical' do
        expect(nrom.mirroring).to eq(:vertical)
      end
    end
  end

  describe '#irq?' do
    subject(:nrom) { described_class.new(cartridge) }

    let(:cartridge) { Cartridges.build }

    it 'is false' do
      expect(nrom).not_to be_irq
    end
  end
end
