# frozen_string_literal: true

# MMC3, iNES mapper 4 (https://www.nesdev.org/wiki/MMC3). "4 pairs of registers at $8000-$9FFF, $A000-$BFFF,
# $C000-$DFFF, and $E000-$FFFF", even and odd addresses: bank select (R0-R7 in bits 2-0, PRG mode in bit 6, CHR A12
# inversion in bit 7), bank data, mirroring, PRG RAM protect (ignored, plan 21 decision 4), IRQ latch, IRQ reload, IRQ
# disable, IRQ enable. PRG in 8 KiB banks: mode 0 shows R6, R7, the second-last and the last bank at $8000, $A000,
# $C000, $E000; mode 1 swaps $8000 and $C000. CHR: R0 and R1 are 2 KiB banks ("The lowest bit is ignored"), R2-R5
# 1 KiB banks, at $0000-$0FFF and $1000-$1FFF, or the other way round with the inversion. $A000 bit 0: 0 connects CIRAM
# A10 to PPU A10 (vertical mirroring), 1 to A11 (horizontal), "no effect on cartridges with hardwired 4-screen VRAM".
# The numbered banks below hold their own number in every byte (Cartridges.numbered_banks): 256 KiB of PRG ROM in
# 32 banks of 8 KiB, 128 KiB of CHR ROM in 128 banks of 1 KiB, as Super Mario Bros. 3.
RSpec.describe Ruby::Nes::Mappers::Mmc3 do
  describe '#cpu_read' do
    context 'when the address is in PRG RAM' do
      # "Many emulators choose not to implement them [...] to avoid an incompatibility with the MMC6": $A001 with bit 7
      # clear would disable the RAM; it is ignored.
      subject(:board) { described_class.new(Cartridges.build(prg_rom: Array.new(262_144, 0xEA), mapper_number: 4)) }

      before do
        board.cpu_write(0xA001, 0x00)
        board.cpu_write(0x6000, 0x5A)
      end

      it 'returns the byte written there, whatever $A001 says' do
        expect(board.cpu_read(0x6000, 0x00)).to eq(0x5A)
      end
    end

    context 'when the address is in PRG ROM' do
      context 'and the PRG mode is 0' do
        subject(:board) { described_class.new(cartridge) }

        let(:cartridge) do
          Cartridges.build(prg_rom: Cartridges.numbered_banks(count: 32, size: 8_192), mapper_number: 4)
        end

        before do
          board.cpu_write(0x8000, 0x06)
          board.cpu_write(0x8001, 5)
          board.cpu_write(0x8000, 0x07)
          board.cpu_write(0x8001, 9)
        end

        context 'and it is $8000' do
          it 'returns a byte of the R6 bank' do
            expect(board.cpu_read(0x8000, 0x00)).to eq(5)
          end
        end

        context 'and it is $A000' do
          it 'returns a byte of the R7 bank' do
            expect(board.cpu_read(0xA000, 0x00)).to eq(9)
          end
        end

        context 'and it is $C000' do
          it 'returns a byte of the second-last bank' do
            expect(board.cpu_read(0xC000, 0x00)).to eq(30)
          end
        end

        context 'and it is $FFFF' do
          it 'returns a byte of the last bank' do
            expect(board.cpu_read(0xFFFF, 0x00)).to eq(31)
          end
        end
      end

      context 'and the PRG mode is 1' do
        subject(:board) { described_class.new(cartridge) }

        let(:cartridge) do
          Cartridges.build(prg_rom: Cartridges.numbered_banks(count: 32, size: 8_192), mapper_number: 4)
        end

        before do
          board.cpu_write(0x8000, 0x46)
          board.cpu_write(0x8001, 5)
          board.cpu_write(0x8000, 0x47)
          board.cpu_write(0x8001, 9)
        end

        context 'and it is $8000' do
          it 'returns a byte of the second-last bank' do
            expect(board.cpu_read(0x8000, 0x00)).to eq(30)
          end
        end

        context 'and it is $A000' do
          it 'returns a byte of the R7 bank' do
            expect(board.cpu_read(0xA000, 0x00)).to eq(9)
          end
        end

        context 'and it is $C000' do
          it 'returns a byte of the R6 bank' do
            expect(board.cpu_read(0xC000, 0x00)).to eq(5)
          end
        end

        context 'and it is $FFFF' do
          it 'returns a byte of the last bank' do
            expect(board.cpu_read(0xFFFF, 0x00)).to eq(31)
          end
        end
      end
    end
  end

  describe '#ppu_read' do
    context 'when CHR A12 inversion is off' do
      # R0 = 10 shows 1 KiB banks 10 and 11; R1 = 21 is odd, its low bit ignored: banks 20 and 21.
      subject(:board) { described_class.new(cartridge).tap { |mmc3| mmc3.ppu = ppu } }

      let(:cartridge) do
        Cartridges.build(
          prg_rom: Array.new(262_144, 0xEA),
          chr_rom: Cartridges.numbered_banks(count: 128, size: 1_024),
          mapper_number: 4
        )
      end

      let(:ppu) { instance_double(Ruby::Nes::Ppu, elapsed_dots: 0) }

      before do
        [10, 21, 40, 41, 42, 43].each_with_index do |bank, register|
          board.cpu_write(0x8000, register)
          board.cpu_write(0x8001, bank)
        end
      end

      context 'and the address is $0000' do
        it 'returns a byte of the first half of the R0 bank' do
          expect(board.ppu_read(0x0000)).to eq(10)
        end
      end

      context 'and the address is $0400' do
        it 'returns a byte of the second half of the R0 bank' do
          expect(board.ppu_read(0x0400)).to eq(11)
        end
      end

      context 'and the address is $0800' do
        it 'returns a byte of the first half of the R1 bank, its low bit ignored' do
          expect(board.ppu_read(0x0800)).to eq(20)
        end
      end

      context 'and the address is $0C00' do
        it 'returns a byte of the second half of the R1 bank' do
          expect(board.ppu_read(0x0C00)).to eq(21)
        end
      end

      context 'and the address is $1000' do
        it 'returns a byte of the R2 bank' do
          expect(board.ppu_read(0x1000)).to eq(40)
        end
      end

      context 'and the address is $1400' do
        it 'returns a byte of the R3 bank' do
          expect(board.ppu_read(0x1400)).to eq(41)
        end
      end

      context 'and the address is $1800' do
        it 'returns a byte of the R4 bank' do
          expect(board.ppu_read(0x1800)).to eq(42)
        end
      end

      context 'and the address is $1FFF' do
        it 'returns a byte of the R5 bank' do
          expect(board.ppu_read(0x1FFF)).to eq(43)
        end
      end
    end

    context 'when CHR A12 inversion is on' do
      subject(:board) { described_class.new(cartridge).tap { |mmc3| mmc3.ppu = ppu } }

      let(:cartridge) do
        Cartridges.build(
          prg_rom: Array.new(262_144, 0xEA),
          chr_rom: Cartridges.numbered_banks(count: 128, size: 1_024),
          mapper_number: 4
        )
      end

      let(:ppu) { instance_double(Ruby::Nes::Ppu, elapsed_dots: 0) }

      before do
        [10, 21, 40, 41, 42, 43].each_with_index do |bank, register|
          board.cpu_write(0x8000, 0x80 | register)
          board.cpu_write(0x8001, bank)
        end
      end

      context 'and the address is $0000' do
        it 'returns a byte of the R2 bank' do
          expect(board.ppu_read(0x0000)).to eq(40)
        end
      end

      context 'and the address is $0400' do
        it 'returns a byte of the R3 bank' do
          expect(board.ppu_read(0x0400)).to eq(41)
        end
      end

      context 'and the address is $0800' do
        it 'returns a byte of the R4 bank' do
          expect(board.ppu_read(0x0800)).to eq(42)
        end
      end

      context 'and the address is $0FFF' do
        it 'returns a byte of the R5 bank' do
          expect(board.ppu_read(0x0FFF)).to eq(43)
        end
      end

      context 'and the address is $1000' do
        it 'returns a byte of the first half of the R0 bank' do
          expect(board.ppu_read(0x1000)).to eq(10)
        end
      end

      context 'and the address is $1400' do
        it 'returns a byte of the second half of the R0 bank' do
          expect(board.ppu_read(0x1400)).to eq(11)
        end
      end

      context 'and the address is $1800' do
        it 'returns a byte of the first half of the R1 bank, its low bit ignored' do
          expect(board.ppu_read(0x1800)).to eq(20)
        end
      end

      context 'and the address is $1C00' do
        it 'returns a byte of the second half of the R1 bank' do
          expect(board.ppu_read(0x1C00)).to eq(21)
        end
      end
    end

    context 'when the board watches A12' do
      subject(:board) { described_class.new(cartridge, a12_watcher:) }

      let(:cartridge) do
        Cartridges.build(chr_rom: Cartridges.numbered_banks(count: 8, size: 1_024), mapper_number: 4)
      end
      let(:a12_watcher) { instance_double(Ruby::Nes::Mappers::Mmc3::A12Watcher, watch: nil) }

      # At power-up R0 is 0: $0400 is the second half of its 2 KiB bank.
      it 'hands the address to the A12 watcher and returns the byte', :aggregate_failures do
        expect(board.ppu_read(0x0400)).to eq(1)
        expect(a12_watcher).to have_received(:watch).with(0x0400)
      end
    end
  end

  describe '#ppu_write' do
    subject(:board) { described_class.new(cartridge, a12_watcher:) }

    let(:cartridge) { Cartridges.build(chr_rom: [], mapper_number: 4) }
    let(:a12_watcher) { instance_double(Ruby::Nes::Mappers::Mmc3::A12Watcher, watch: nil) }

    before { board.ppu_write(0x1000, 0x5A) }

    it 'hands the address to the A12 watcher and keeps the byte in CHR RAM', :aggregate_failures do
      expect(a12_watcher).to have_received(:watch).with(0x1000)
      expect(board.ppu_read(0x1000)).to eq(0x5A)
    end
  end

  describe '#ppu_address' do
    subject(:board) { described_class.new(Cartridges.build(mapper_number: 4), a12_watcher:) }

    let(:a12_watcher) { instance_double(Ruby::Nes::Mappers::Mmc3::A12Watcher, watch: nil) }

    before { board.ppu_address(0x1000) }

    it 'hands the address to the A12 watcher' do
      expect(a12_watcher).to have_received(:watch).with(0x1000)
    end
  end

  describe '#earliest_irq_cycle' do
    subject(:board) { described_class.new(Cartridges.build(mapper_number: 4), irq_counter:) }

    let(:irq_counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, earliest_irq_cycle: 640) }

    it "answers the IRQ counter's earliest IRQ cycle" do
      expect(board.earliest_irq_cycle(600)).to eq(640)
    end
  end

  describe '#mirroring' do
    context 'when the header asks for four-screen VRAM' do
      subject(:board) do
        described_class.new(Cartridges.build(mapper_number: 4, alternative_nametables: true))
      end

      before { board.cpu_write(0xA000, 0x01) }

      it 'stays four-screen' do
        expect(board.mirroring).to eq(:four_screen)
      end
    end

    context 'when the header does not ask for four-screen VRAM' do
      context 'and $A000 was never written' do
        subject(:board) { described_class.new(Cartridges.build(mapper_number: 4, mirroring: :horizontal)) }

        it "is the header's" do
          expect(board.mirroring).to eq(:horizontal)
        end
      end

      context 'and $A000 bit 0 is clear' do
        subject(:board) { described_class.new(Cartridges.build(mapper_number: 4, mirroring: :horizontal)) }

        before { board.cpu_write(0xA000, 0xFE) }

        it 'is vertical' do
          expect(board.mirroring).to eq(:vertical)
        end
      end

      # The nametables start horizontal, $2005 shared with $2405; $A000 bit 0 clear then makes them vertical.
      context 'and its nametables were given' do
        subject(:board) { described_class.new(Cartridges.build(mapper_number: 4, mirroring: :horizontal)) }

        let!(:nametables) { Ruby::Nes::PpuBus::Nametables.new(mapper: board) }

        before do
          nametables.write(0x2005, 0x11)
          board.cpu_write(0xA000, 0xFE)
        end

        it 'tells them the arrangement selected' do
          expect(nametables.read(0x2405)).to eq(0x00)
        end
      end

      context 'and $A000 bit 0 is set' do
        subject(:board) { described_class.new(Cartridges.build(mapper_number: 4, mirroring: :vertical)) }

        before { board.cpu_write(0xBFFE, 0x01) }

        it 'is horizontal' do
          expect(board.mirroring).to eq(:horizontal)
        end
      end
    end
  end

  describe '#cpu_write' do
    context 'when the address is $C000' do
      subject(:board) { described_class.new(Cartridges.build(mapper_number: 4), irq_counter:) }

      let(:irq_counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, :latch= => nil) }

      before { board.cpu_write(0xC000, 0x7F) }

      it "sets the IRQ counter's latch" do
        expect(irq_counter).to have_received(:latch=).with(0x7F)
      end
    end

    context 'when the address is $C001' do
      subject(:board) { described_class.new(Cartridges.build(mapper_number: 4), irq_counter:) }

      let(:irq_counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, request_reload: nil) }

      before { board.cpu_write(0xC001, 0x7F) }

      it 'asks the IRQ counter to reload' do
        expect(irq_counter).to have_received(:request_reload)
      end
    end

    context 'when the address is $E000' do
      subject(:board) { described_class.new(Cartridges.build(mapper_number: 4), irq_counter:) }

      let(:irq_counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, disable: nil) }

      before { board.cpu_write(0xE000, 0x7F) }

      it 'disables the IRQ' do
        expect(irq_counter).to have_received(:disable)
      end
    end

    context 'when the address is $E001' do
      subject(:board) { described_class.new(Cartridges.build(mapper_number: 4), irq_counter:) }

      let(:irq_counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, enable: nil) }

      before { board.cpu_write(0xE001, 0x7F) }

      it 'enables the IRQ' do
        expect(irq_counter).to have_received(:enable)
      end
    end

    context 'when the address is $FFFE, the last even address of $E000-$FFFF' do
      subject(:board) { described_class.new(Cartridges.build(mapper_number: 4), irq_counter:) }

      let(:irq_counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, disable: nil) }

      before { board.cpu_write(0xFFFE, 0x7F) }

      it 'disables the IRQ' do
        expect(irq_counter).to have_received(:disable)
      end
    end
  end

  describe '#cpu=' do
    subject(:board) { described_class.new(Cartridges.build(mapper_number: 4), irq_counter:) }

    let(:irq_counter) { instance_double(Ruby::Nes::Mappers::Mmc3::IrqCounter, :cpu= => nil) }
    let(:cpu) { instance_double(Ruby::Nes::Cpu) }

    it 'gives the IRQ counter the CPU, its IRQ line' do
      board.cpu = cpu
      expect(irq_counter).to have_received(:cpu=).with(cpu)
    end
  end

  describe '#ppu=' do
    subject(:board) { described_class.new(Cartridges.build(mapper_number: 4), a12_watcher:) }

    let(:a12_watcher) { instance_double(Ruby::Nes::Mappers::Mmc3::A12Watcher, :ppu= => nil) }
    let(:ppu) { instance_double(Ruby::Nes::Ppu) }

    it 'gives the A12 watcher the PPU, its clock' do
      board.ppu = ppu
      expect(a12_watcher).to have_received(:ppu=).with(ppu)
    end
  end
end
