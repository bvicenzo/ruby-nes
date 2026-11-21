# frozen_string_literal: true

RSpec.describe Ruby::Nes::Mappers::Base do
  describe '#cpu_read' do
    context 'when the address is below PRG RAM' do
      let(:cartridge) { Cartridges.build }

      context 'and the board has no PRG RAM' do
        subject(:board) { described_class.new(cartridge) }

        context 'and it is $4020' do
          it 'returns the data bus value' do
            expect(board.cpu_read(0x4020, 0x5A)).to eq(0x5A)
          end
        end

        context 'and it is $5FFF' do
          it 'returns the data bus value' do
            expect(board.cpu_read(0x5FFF, 0x5A)).to eq(0x5A)
          end
        end
      end

      context 'and the board has PRG RAM' do
        subject(:board) { described_class.new(cartridge, prg_ram: true) }

        context 'and it is $4020' do
          it 'returns the data bus value' do
            expect(board.cpu_read(0x4020, 0x5A)).to eq(0x5A)
          end
        end

        context 'and it is $5FFF' do
          it 'returns the data bus value' do
            expect(board.cpu_read(0x5FFF, 0x5A)).to eq(0x5A)
          end
        end
      end
    end

    context 'when the address is in the PRG RAM range' do
      let(:cartridge) { Cartridges.build }

      context 'but the board has no PRG RAM' do
        subject(:board) { described_class.new(cartridge) }

        context 'and it is $6000' do
          it 'returns the data bus value' do
            expect(board.cpu_read(0x6000, 0x5A)).to eq(0x5A)
          end
        end

        context 'and it is $7FFF' do
          it 'returns the data bus value' do
            expect(board.cpu_read(0x7FFF, 0x5A)).to eq(0x5A)
          end
        end
      end

      context 'and the board has PRG RAM' do
        subject(:board) { described_class.new(cartridge, prg_ram: true) }

        it 'returns zero before anything is written' do
          expect(board.cpu_read(0x6000, 0x5A)).to eq(0x00)
        end
      end
    end

    context 'when the address is in PRG ROM' do
      subject(:board) { described_class.new(cartridge) }

      context 'and the PRG ROM is 16 KiB' do
        let(:cartridge) { Cartridges.build(prg_rom: [0x11, *Array.new(16_382, 0xEA), 0x22]) }

        context 'and the address is $8000' do
          it 'returns the first PRG ROM byte' do
            expect(board.cpu_read(0x8000, 0x5A)).to eq(0x11)
          end
        end

        context 'and the address is $BFFF' do
          it 'returns the last PRG ROM byte' do
            expect(board.cpu_read(0xBFFF, 0x5A)).to eq(0x22)
          end
        end

        context 'and the address is $C000' do
          it 'returns the first PRG ROM byte' do
            expect(board.cpu_read(0xC000, 0x5A)).to eq(0x11)
          end
        end

        context 'and the address is $FFFF' do
          it 'returns the last PRG ROM byte' do
            expect(board.cpu_read(0xFFFF, 0x5A)).to eq(0x22)
          end
        end
      end

      context 'and the PRG ROM is 32 KiB' do
        let(:cartridge) do
          Cartridges.build(prg_rom: [0x11, *Array.new(16_382, 0xEA), 0x22, 0x33, *Array.new(16_382, 0xEA), 0x44])
        end

        context 'and the address is $8000' do
          it 'returns the first PRG ROM byte' do
            expect(board.cpu_read(0x8000, 0x5A)).to eq(0x11)
          end
        end

        context 'and the address is $BFFF' do
          it 'returns the last byte of the first half' do
            expect(board.cpu_read(0xBFFF, 0x5A)).to eq(0x22)
          end
        end

        context 'and the address is $C000' do
          it 'returns the first byte of the second half' do
            expect(board.cpu_read(0xC000, 0x5A)).to eq(0x33)
          end
        end

        context 'and the address is $FFFF' do
          it 'returns the last PRG ROM byte' do
            expect(board.cpu_read(0xFFFF, 0x5A)).to eq(0x44)
          end
        end
      end

      context 'and the PRG ROM is larger than 32 KiB' do
        # 128 KiB: the six middle 16 KiB banks are all $55, so $C000 tells the last 16 KiB from the second.
        let(:cartridge) { Cartridges.build(prg_rom: [*first_sixteen_kib, *Array.new(98_304, 0x55), *last_sixteen_kib]) }
        let(:first_sixteen_kib) { [0x11, *Array.new(16_382, 0xEA), 0x22] }
        let(:last_sixteen_kib) { [0x33, *Array.new(16_382, 0xEA), 0x44] }

        context 'and the address is $8000' do
          it 'returns the first PRG ROM byte' do
            expect(board.cpu_read(0x8000, 0x5A)).to eq(0x11)
          end
        end

        context 'and the address is $BFFF' do
          it 'returns the last byte of the first 16 KiB' do
            expect(board.cpu_read(0xBFFF, 0x5A)).to eq(0x22)
          end
        end

        context 'and the address is $C000' do
          it 'returns the first byte of the last 16 KiB' do
            expect(board.cpu_read(0xC000, 0x5A)).to eq(0x33)
          end
        end

        context 'and the address is $FFFF' do
          it 'returns the last PRG ROM byte' do
            expect(board.cpu_read(0xFFFF, 0x5A)).to eq(0x44)
          end
        end
      end
    end
  end

  describe '#cpu_write' do
    context 'when the address is below PRG RAM' do
      subject(:board) { described_class.new(Cartridges.build, prg_ram: true) }

      before { board.cpu_write(0x5FFF, 0x77) }

      it 'keeps reading the data bus value there' do
        expect(board.cpu_read(0x5FFF, 0x5A)).to eq(0x5A)
      end

      it 'leaves PRG RAM unchanged' do
        expect(board.cpu_read(0x7FFF, 0x5A)).to eq(0x00)
      end
    end

    context 'when the address is in the PRG RAM range' do
      context 'but the board has no PRG RAM' do
        subject(:board) { described_class.new(Cartridges.build) }

        before { board.cpu_write(0x6000, 0x77) }

        it 'keeps reading the data bus value there' do
          expect(board.cpu_read(0x6000, 0x5A)).to eq(0x5A)
        end
      end

      context 'and the board has PRG RAM' do
        subject(:board) { described_class.new(Cartridges.build, prg_ram: true) }

        context 'and it is $6000' do
          before { board.cpu_write(0x6000, 0x77) }

          it 'is read back at the same address' do
            expect(board.cpu_read(0x6000, 0x5A)).to eq(0x77)
          end
        end

        context 'and it is $7FFF' do
          before { board.cpu_write(0x7FFF, 0x77) }

          it 'is read back at the same address' do
            expect(board.cpu_read(0x7FFF, 0x5A)).to eq(0x77)
          end
        end
      end
    end

    context 'when the address is in PRG ROM' do
      subject(:board) { described_class.new(cartridge, prg_ram: true) }

      let(:cartridge) { Cartridges.build(prg_rom: [0x11, *Array.new(16_382, 0xEA), 0x22]) }

      before { board.cpu_write(0x8000, 0x77) }

      it 'leaves the PRG ROM byte unchanged' do
        expect(board.cpu_read(0x8000, 0x5A)).to eq(0x11)
      end

      it 'leaves PRG RAM unchanged' do
        expect(board.cpu_read(0x6000, 0x5A)).to eq(0x00)
      end
    end
  end

  describe '#ppu_read' do
    subject(:board) { described_class.new(cartridge) }

    context 'when the board has CHR ROM' do
      let(:cartridge) { Cartridges.build(chr_rom: [0x33, *Array.new(8_190, 0xEA), 0x44]) }

      context 'and the address is $0000' do
        it 'returns the first CHR ROM byte' do
          expect(board.ppu_read(0x0000)).to eq(0x33)
        end
      end

      context 'and the address is $1FFF' do
        it 'returns the last CHR ROM byte' do
          expect(board.ppu_read(0x1FFF)).to eq(0x44)
        end
      end
    end

    context 'when the board has CHR RAM' do
      let(:cartridge) { Cartridges.build(chr_rom: []) }

      it 'returns zero before anything is written' do
        expect(board.ppu_read(0x1FFF)).to eq(0x00)
      end
    end
  end

  describe '#ppu_write' do
    subject(:board) { described_class.new(cartridge) }

    context 'when the board has CHR ROM' do
      let(:cartridge) { Cartridges.build(chr_rom: [0x33, *Array.new(8_190, 0xEA), 0x44]) }

      before { board.ppu_write(0x0000, 0x77) }

      it 'leaves the CHR ROM byte unchanged' do
        expect(board.ppu_read(0x0000)).to eq(0x33)
      end
    end

    context 'when the board has CHR RAM' do
      let(:cartridge) { Cartridges.build(chr_rom: []) }

      context 'and the address is $0000' do
        before { board.ppu_write(0x0000, 0x77) }

        it 'is read back at the same address' do
          expect(board.ppu_read(0x0000)).to eq(0x77)
        end
      end

      context 'and the address is $1FFF' do
        before { board.ppu_write(0x1FFF, 0x77) }

        it 'is read back at the same address' do
          expect(board.ppu_read(0x1FFF)).to eq(0x77)
        end
      end
    end
  end

  describe '#mirroring' do
    subject(:board) { described_class.new(cartridge) }

    context 'when the header says horizontal' do
      let(:cartridge) { Cartridges.build(mirroring: :horizontal) }

      it 'is horizontal' do
        expect(board.mirroring).to eq(:horizontal)
      end
    end

    context 'when the header says vertical' do
      let(:cartridge) { Cartridges.build(mirroring: :vertical) }

      it 'is vertical' do
        expect(board.mirroring).to eq(:vertical)
      end
    end
  end

  describe '#irq?' do
    subject(:board) { described_class.new(Cartridges.build) }

    it 'is false' do
      expect(board).not_to be_irq
    end
  end
end
