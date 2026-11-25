# frozen_string_literal: true

# MMC1, iNES mapper 1 (https://www.nesdev.org/wiki/MMC1). Registers are loaded through the serial port, five writes
# low bit first, the fifth write's address bits 14-13 picking Control ($8000-$9FFF), CHR bank 0 ($A000-$BFFF), CHR
# bank 1 ($C000-$DFFF) or PRG bank ($E000-$FFFF). Control is `CPPMM`: nametable arrangement MM, PRG mode PP, CHR mode
# C. PRG ROM here is numbered 16 KiB banks and CHR numbered 4 KiB banks (Cartridges.numbered_banks), so a read returns
# the number of the bank a window shows. Power-up: Control $0C, the other registers 0 (plan 20, decision 4).
RSpec.describe Ruby::Nes::Mappers::Mmc1 do
  describe '#mirroring' do
    subject(:mmc1) { described_class.new(cartridge) }

    let(:cartridge) { Cartridges.build(mirroring: :vertical) }
    let(:programmer) { Mmc1Programmer.new(mmc1) }

    context 'when nothing was written yet' do
      it 'is the lower single screen, whatever the header says' do
        expect(mmc1.mirroring).to eq(:single_screen_lower)
      end
    end

    context 'when the arrangement is 0' do
      before do
        programmer.load(0x8000, 0b0_1111)
        programmer.load(0x8000, 0b0_1100)
      end

      it 'is the lower single screen' do
        expect(mmc1.mirroring).to eq(:single_screen_lower)
      end
    end

    context 'when the arrangement is 1' do
      before { programmer.load(0x8000, 0b0_1101) }

      it 'is the upper single screen' do
        expect(mmc1.mirroring).to eq(:single_screen_upper)
      end
    end

    context 'when the arrangement is 2' do
      before { programmer.load(0x8000, 0b0_1110) }

      it 'is vertical' do
        expect(mmc1.mirroring).to eq(:vertical)
      end
    end

    context 'when the arrangement is 3' do
      before { programmer.load(0x8000, 0b0_1111) }

      it 'is horizontal' do
        expect(mmc1.mirroring).to eq(:horizontal)
      end
    end

    context 'when a reset follows' do
      # "The CHR bank mode and nametable arrangement are not altered."
      before do
        programmer.load(0x8000, 0b0_0010)
        programmer.write(0x8000, 0x80)
      end

      it 'keeps the arrangement' do
        expect(mmc1.mirroring).to eq(:vertical)
      end
    end

    # The nametables start on the lower single screen, where $2005 is written; arrangement 2 then makes them vertical.
    context 'when its nametables were given' do
      let!(:nametables) { Ruby::Nes::PpuBus::Nametables.new(mapper: mmc1) }

      before do
        nametables.write(0x2005, 0x11)
        programmer.load(0x8000, 0b0_1110)
      end

      it 'tells them the arrangement selected', :aggregate_failures do
        expect(nametables.read(0x2805)).to eq(0x11)
        expect(nametables.read(0x2405)).to eq(0x00)
      end
    end
  end

  describe '#cpu_read' do
    subject(:mmc1) { described_class.new(cartridge) }

    let(:programmer) { Mmc1Programmer.new(mmc1) }

    context 'when the address is in PRG RAM' do
      let(:cartridge) { Cartridges.build }

      context 'and PRG RAM is on, as at power-up' do
        before { mmc1.cpu_write(0x6000, 0x42) }

        it 'returns the byte kept there' do
          expect(mmc1.cpu_read(0x6000, 0x5A)).to eq(0x42)
        end
      end

      context 'but PRG bank bit 4 turned PRG RAM off' do
        before do
          mmc1.cpu_write(0x6000, 0x42)
          programmer.load(0xE000, 0x10)
        end

        it 'returns the data bus value' do
          expect(mmc1.cpu_read(0x6000, 0x5A)).to eq(0x5A)
        end
      end

      context 'and PRG bank bit 4 turned PRG RAM on again' do
        before do
          mmc1.cpu_write(0x6000, 0x42)
          programmer.load(0xE000, 0x10)
          programmer.load(0xE000, 0x00)
        end

        it 'returns the byte kept there' do
          expect(mmc1.cpu_read(0x6000, 0x5A)).to eq(0x42)
        end
      end
    end

    context 'when the address is in PRG ROM' do
      context 'and the PRG ROM is 80 KiB, not a power of two' do
        # Five banks, as blargg's cpu_interrupts.nes: bank 15 would wrap to bank 0 (plan 19, decision 5).
        let(:cartridge) { Cartridges.build(prg_rom: Cartridges.numbered_banks(count: 5, size: 16_384)) }

        context 'and nothing was written yet' do
          it 'fixes the last bank at $C000' do
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(4)
          end
        end
      end

      context 'and the PRG ROM is 256 KiB' do
        let(:cartridge) { Cartridges.build(prg_rom: Cartridges.numbered_banks(count: 16, size: 16_384)) }

        context 'and nothing was written yet' do
          it 'shows the first bank at $8000 and the last at $C000', :aggregate_failures do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(0)
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(15)
          end
        end

        context 'and the PRG mode is 0' do
          before do
            programmer.load(0x8000, 0b0_0000)
            programmer.load(0xE000, 5)
          end

          it 'shows the 32 KiB pair of the bank, low bit ignored', :aggregate_failures do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(4)
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(5)
          end
        end

        context 'and the PRG mode is 1' do
          before do
            programmer.load(0x8000, 0b0_0100)
            programmer.load(0xE000, 5)
          end

          it 'shows the 32 KiB pair of the bank, low bit ignored', :aggregate_failures do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(4)
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(5)
          end
        end

        context 'and the PRG mode is 2' do
          before do
            programmer.load(0x8000, 0b0_1000)
            programmer.load(0xE000, 5)
          end

          it 'fixes the first bank at $8000 and shows the bank at $C000', :aggregate_failures do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(0)
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(5)
          end
        end

        context 'and the PRG mode is 3' do
          before do
            programmer.load(0x8000, 0b0_1100)
            programmer.load(0xE000, 5)
          end

          it 'shows the bank at $8000 and fixes the last bank at $C000', :aggregate_failures do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(5)
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(15)
          end
        end

        context 'and CHR bank 0 bit 4 is set' do
          # Only a 512 KiB PRG ROM takes the outer bank from it (plan 20, decision 7).
          before do
            programmer.load(0xA000, 0x10)
            programmer.load(0xE000, 5)
          end

          it 'leaves the PRG banks as they are', :aggregate_failures do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(5)
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(15)
          end
        end
      end

      context 'and the PRG ROM is 512 KiB' do
        # SUROM: CHR bank 0 bit 4 "Select 256 KiB PRG-ROM bank", which "applies to all the PRG area, including the
        # normally "fixed" bank".
        let(:cartridge) { Cartridges.build(prg_rom: Cartridges.numbered_banks(count: 32, size: 16_384)) }

        context 'and CHR bank 0 bit 4 is clear' do
          before do
            programmer.load(0xA000, 0x00)
            programmer.load(0xE000, 5)
          end

          it 'shows the first 256 KiB', :aggregate_failures do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(5)
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(15)
          end
        end

        context 'and CHR bank 0 bit 4 is set' do
          before do
            programmer.load(0xA000, 0x10)
            programmer.load(0xE000, 5)
          end

          it 'shows the second 256 KiB, fixed bank included', :aggregate_failures do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(21)
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(31)
          end
        end

        context 'and the PRG mode is 2 with CHR bank 0 bit 4 set' do
          before do
            programmer.load(0x8000, 0b0_1000)
            programmer.load(0xA000, 0x10)
            programmer.load(0xE000, 5)
          end

          it 'fixes the first bank of the second 256 KiB at $8000', :aggregate_failures do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(16)
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(21)
          end
        end

        context 'and PRG bank bit 4 is set' do
          # Bit 4 of the PRG bank turns PRG RAM off; it selects no bank.
          before { programmer.load(0xE000, 0x15) }

          it 'selects the bank of bits 3-0' do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(5)
          end
        end

        context 'and the CHR mode is 4 KiB with only CHR bank 1 bit 4 set' do
          # The outer bank comes from CHR bank 0 in both CHR modes (plan 20, decision 7).
          before do
            programmer.load(0x8000, 0b1_1100)
            programmer.load(0xA000, 0x00)
            programmer.load(0xC000, 0x10)
            programmer.load(0xE000, 5)
          end

          it 'shows the first 256 KiB', :aggregate_failures do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(5)
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(15)
          end
        end
      end
    end
  end

  describe '#cpu_write' do
    subject(:mmc1) { described_class.new(cartridge) }

    let(:programmer) { Mmc1Programmer.new(mmc1) }

    context 'when the address is in PRG RAM' do
      context 'but PRG RAM is off' do
        let(:cartridge) { Cartridges.build }

        before do
          programmer.load(0xE000, 0x10)
          mmc1.cpu_write(0x6000, 0x42)
          programmer.load(0xE000, 0x00)
        end

        it 'leaves PRG RAM unchanged' do
          expect(mmc1.cpu_read(0x6000, 0x5A)).to eq(0x00)
        end
      end
    end

    context 'when the address is in the registers' do
      let(:cartridge) do
        Cartridges.build(
          prg_rom: Cartridges.numbered_banks(count: 16, size: 16_384),
          chr_rom: Cartridges.numbered_banks(count: 8, size: 4_096)
        )
      end

      # "Only on the fifth write does the address matter": the first four go elsewhere.
      context 'and the fifth write goes to $9FFF' do
        before do
          programmer.write(0xE000, 0)
          programmer.write(0xE000, 1)
          programmer.write(0xE000, 1)
          programmer.write(0xE000, 1)
          programmer.write(0x9FFF, 0)
        end

        it 'loads Control' do
          expect(mmc1.mirroring).to eq(:vertical)
        end
      end

      context 'and the fifth write goes to $A000' do
        # Bank 2, even: the power-up CHR mode is 8 KiB, which ignores the low bit.
        before do
          programmer.write(0x8000, 0)
          programmer.write(0x8000, 1)
          programmer.write(0x8000, 0)
          programmer.write(0x8000, 0)
          programmer.write(0xA000, 0)
        end

        it 'loads CHR bank 0' do
          expect(mmc1.ppu_read(0x0000)).to eq(2)
        end
      end

      context 'and the fifth write goes to $DFFF' do
        before do
          programmer.load(0x8000, 0b1_1100)
          programmer.write(0x8000, 1)
          programmer.write(0x8000, 0)
          programmer.write(0x8000, 1)
          programmer.write(0x8000, 0)
          programmer.write(0xDFFF, 0)
        end

        it 'loads CHR bank 1' do
          expect(mmc1.ppu_read(0x1000)).to eq(5)
        end
      end

      context 'and the fifth write goes to $E000' do
        before do
          programmer.write(0x8000, 1)
          programmer.write(0x8000, 0)
          programmer.write(0x8000, 1)
          programmer.write(0x8000, 0)
          programmer.write(0xE000, 0)
        end

        it 'loads the PRG bank' do
          expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(5)
        end
      end

      context 'and the write sets bit 7' do
        # A reset ORs Control with $0C: PRG mode 3; "The CHR bank mode and nametable arrangement are not altered."
        before do
          programmer.load(0x8000, 0b1_1000)
          programmer.load(0xC000, 6)
          programmer.load(0xE000, 5)
          programmer.write(0x8000, 0x80)
        end

        it 'shows the bank at $8000 and fixes the last bank at $C000', :aggregate_failures do
          expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(5)
          expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(15)
        end

        it 'keeps the CHR mode' do
          expect(mmc1.ppu_read(0x1000)).to eq(6)
        end
      end

      context 'and a read-modify-write instruction writes twice on one cycle' do
        context 'and the second write sets bit 7' do
          # Shinsenden: "the bit 7 reset is never ignored".
          before do
            programmer.load(0x8000, 0b0_1000)
            programmer.load(0xE000, 5)
            programmer.read_modify_write(0x8000, original: 0x00, modified: 0x80)
          end

          it 'resets', :aggregate_failures do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(5)
            expect(mmc1.cpu_read(0xC000, 0x5A)).to eq(15)
          end
        end

        context 'and the first write sets bit 7' do
          # Bill & Ted's INC on a $FF byte: the $00 on the next cycle is ignored, so the next load counts five writes.
          before do
            programmer.read_modify_write(0x8000, original: 0xFF, modified: 0x00)
            programmer.load(0xE000, 7)
          end

          it 'ignores the second write' do
            expect(mmc1.cpu_read(0x8000, 0x5A)).to eq(7)
          end
        end
      end
    end
  end

  describe '#ppu_read' do
    subject(:mmc1) { described_class.new(cartridge) }

    let(:cartridge) { Cartridges.build(chr_rom: Cartridges.numbered_banks(count: 8, size: 4_096)) }
    let(:programmer) { Mmc1Programmer.new(mmc1) }

    context 'when nothing was written yet' do
      it 'shows the first 8 KiB', :aggregate_failures do
        expect(mmc1.ppu_read(0x0000)).to eq(0)
        expect(mmc1.ppu_read(0x1000)).to eq(1)
      end
    end

    context 'when the CHR mode is 8 KiB' do
      before do
        programmer.load(0x8000, 0b0_1100)
        programmer.load(0xA000, 3)
        programmer.load(0xC000, 6)
      end

      it 'shows the 8 KiB pair of CHR bank 0, low bit ignored', :aggregate_failures do
        expect(mmc1.ppu_read(0x0000)).to eq(2)
        expect(mmc1.ppu_read(0x1000)).to eq(3)
      end
    end

    context 'when the CHR mode is 4 KiB' do
      before do
        programmer.load(0x8000, 0b1_1100)
        programmer.load(0xA000, 3)
        programmer.load(0xC000, 6)
      end

      it 'shows CHR bank 0 at $0000 and CHR bank 1 at $1000', :aggregate_failures do
        expect(mmc1.ppu_read(0x0000)).to eq(3)
        expect(mmc1.ppu_read(0x1000)).to eq(6)
      end
    end
  end

  describe '#battery_ram' do
    subject(:mmc1) { described_class.new(Cartridges.build(mapper_number: 1, battery: true)) }

    let(:programmer) { Mmc1Programmer.new(mmc1) }

    context 'when PRG bank bit 4 turned PRG RAM off' do
      before do
        mmc1.cpu_write(0x6000, 0x42)
        programmer.load(0xE000, 0x10)
      end

      it 'is still the bytes the CPU wrote before' do
        expect(mmc1.battery_ram).to eq([0x42, *Array.new(8_191, 0x00)])
      end
    end
  end
end
