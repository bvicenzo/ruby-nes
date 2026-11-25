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
        # 128 KiB in sixteen 8 KiB banks, each byte holding its bank's number: $8000-$BFFF shows banks 0 and 1,
        # $C000-$FFFF banks 14 and 15, one per 8 KiB window.
        let(:cartridge) { Cartridges.build(prg_rom: Cartridges.numbered_banks(count: 16, size: 8_192)) }

        context 'and the address is $8000' do
          it 'returns a byte of the first 8 KiB' do
            expect(board.cpu_read(0x8000, 0x5A)).to eq(0)
          end
        end

        context 'and the address is $9FFF' do
          it 'returns a byte of the first 8 KiB' do
            expect(board.cpu_read(0x9FFF, 0x5A)).to eq(0)
          end
        end

        context 'and the address is $A000' do
          it 'returns a byte of the second 8 KiB' do
            expect(board.cpu_read(0xA000, 0x5A)).to eq(1)
          end
        end

        context 'and the address is $C000' do
          it 'returns a byte of the second-last 8 KiB' do
            expect(board.cpu_read(0xC000, 0x5A)).to eq(14)
          end
        end

        context 'and the address is $E000' do
          it 'returns a byte of the last 8 KiB' do
            expect(board.cpu_read(0xE000, 0x5A)).to eq(15)
          end
        end

        context 'and the address is $FFFF' do
          it 'returns a byte of the last 8 KiB' do
            expect(board.cpu_read(0xFFFF, 0x5A)).to eq(15)
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
      context 'and no register sync was given' do
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

      context 'and a register sync was given' do
        # A board with a register (UxROM's bank select) shows whether the PPU caught up before the write took effect:
        # the sync looks at $8000 while it runs.
        subject(:board) do
          Ruby::Nes::Mappers::Uxrom.new(cartridge).tap { |uxrom| uxrom.register_sync = register_sync }
        end

        let(:cartridge) { Cartridges.build(prg_rom: Cartridges.numbered_banks(count: 4, size: 16_384)) }
        let(:register_sync) { instance_double(Ruby::Nes::Console::PpuRegisterSync) }
        let(:bank_while_catching_up) { [] }

        before do
          allow(register_sync).to receive(:catch_up) { bank_while_catching_up.replace([board.cpu_read(0x8000, 0x5A)]) }
          board.cpu_write(0x8000, 2)
        end

        it 'catches the PPU up before the board takes the write', :aggregate_failures do
          expect(bank_while_catching_up).to eq([0])
          expect(board.cpu_read(0x8000, 0x5A)).to eq(2)
        end
      end
    end
  end

  describe '#ppu_read' do
    subject(:board) { described_class.new(cartridge) }

    context 'when the board has CHR ROM' do
      # Eight 1 KiB banks, each byte holding its bank's number, one per 1 KiB window.
      let(:cartridge) { Cartridges.build(chr_rom: Cartridges.numbered_banks(count: 8, size: 1_024)) }

      context 'and the address is $0000' do
        it 'returns a byte of the first 1 KiB' do
          expect(board.ppu_read(0x0000)).to eq(0)
        end
      end

      context 'and the address is $03FF' do
        it 'returns a byte of the first 1 KiB' do
          expect(board.ppu_read(0x03FF)).to eq(0)
        end
      end

      context 'and the address is $0400' do
        it 'returns a byte of the second 1 KiB' do
          expect(board.ppu_read(0x0400)).to eq(1)
        end
      end

      context 'and the address is $1000' do
        it 'returns a byte of the fifth 1 KiB' do
          expect(board.ppu_read(0x1000)).to eq(4)
        end
      end

      context 'and the address is $1FFF' do
        it 'returns a byte of the last 1 KiB' do
          expect(board.ppu_read(0x1FFF)).to eq(7)
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

  describe '#ppu_address' do
    subject(:board) { described_class.new(cartridge) }

    let(:cartridge) { Cartridges.build(chr_rom: Cartridges.numbered_banks(count: 8, size: 1_024)) }

    before { board.ppu_address(0x1000) }

    it 'leaves the pattern tables as they are' do
      expect(board.ppu_read(0x1000)).to eq(4)
    end
  end

  # A board without an IRQ the PPU's fetches clock never makes the PPU catch up for one (plan 28, decision 3).
  describe '#earliest_irq_cycle' do
    subject(:board) { described_class.new(Cartridges.build) }

    it 'answers never' do
      expect(board.earliest_irq_cycle(600)).to eq(described_class::NEVER)
    end
  end

  describe '#mirroring' do
    subject(:board) { described_class.new(cartridge) }

    context 'when the header asks for four-screen VRAM' do
      let(:cartridge) { Cartridges.build(mirroring: :vertical, alternative_nametables: true) }

      it 'is four-screen' do
        expect(board.mirroring).to eq(:four_screen)
      end
    end

    context 'when the header does not ask for four-screen VRAM' do
      context 'and it says horizontal' do
        let(:cartridge) { Cartridges.build(mirroring: :horizontal) }

        it 'is horizontal' do
          expect(board.mirroring).to eq(:horizontal)
        end
      end

      context 'and it says vertical' do
        let(:cartridge) { Cartridges.build(mirroring: :vertical) }

        it 'is vertical' do
          expect(board.mirroring).to eq(:vertical)
        end
      end
    end
  end

  describe '#battery_ram' do
    context 'when the board has no PRG RAM' do
      subject(:board) { described_class.new(cartridge) }

      context 'and the header has no battery flag' do
        let(:cartridge) { Cartridges.build(battery: false) }

        it 'is nil' do
          expect(board.battery_ram).to be_nil
        end
      end

      context 'but the header has the battery flag' do
        let(:cartridge) { Cartridges.build(battery: true) }

        it 'is nil' do
          expect(board.battery_ram).to be_nil
        end
      end
    end

    context 'when the board has PRG RAM' do
      subject(:board) { described_class.new(cartridge, prg_ram: true) }

      context 'but the header has no battery flag' do
        let(:cartridge) { Cartridges.build(battery: false) }

        it 'is nil' do
          expect(board.battery_ram).to be_nil
        end
      end

      context 'and the header has the battery flag' do
        let(:cartridge) { Cartridges.build(battery: true) }

        before do
          board.cpu_write(0x6000, 0x11)
          board.cpu_write(0x7FFF, 0x22)
        end

        it 'is the 8 KiB the CPU wrote, $6000 first and $7FFF last' do
          expect(board.battery_ram).to eq([0x11, *Array.new(8_190, 0x00), 0x22])
        end

        it 'is a copy: changing it changes nothing the CPU reads' do
          board.battery_ram[0] = 0x99

          expect(board.cpu_read(0x6000, 0x5A)).to eq(0x11)
        end
      end
    end
  end

  describe '#battery_ram=' do
    subject(:board) { described_class.new(Cartridges.build(battery: true), prg_ram: true) }

    context 'when the bytes are not 8 KiB' do
      before { board.cpu_write(0x6000, 0x44) }

      it 'raises ArgumentError, leaving PRG RAM as it was', :aggregate_failures do
        expect { board.battery_ram = Array.new(8_191, 0x11) }.to raise_error(ArgumentError, /8191.*8192/)
        expect(board.battery_ram).to eq([0x44, *Array.new(8_191, 0x00)])
      end
    end

    context 'when the bytes are 8 KiB' do
      let(:save) { [0x11, *Array.new(8_190, 0x00), 0x22] }

      it 'puts the bytes where the CPU reads $6000-$7FFF', :aggregate_failures do
        board.battery_ram = save

        expect(board.cpu_read(0x6000, 0x5A)).to eq(0x11)
        expect(board.cpu_read(0x6001, 0x5A)).to eq(0x00)
        expect(board.cpu_read(0x7FFF, 0x5A)).to eq(0x22)
      end

      it 'copies them: changing the given array afterwards changes nothing the CPU reads' do
        board.battery_ram = save
        save[0] = 0x99

        expect(board.cpu_read(0x6000, 0x5A)).to eq(0x11)
      end

      it 'lets the CPU write over a loaded byte' do
        board.battery_ram = save
        board.cpu_write(0x6000, 0x33)

        expect(board.cpu_read(0x6000, 0x5A)).to eq(0x33)
      end
    end
  end
end
