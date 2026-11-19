# frozen_string_literal: true

require 'digest'

# The console (plan 12): the CPU and the PPU run together, the PPU 3 dots per CPU cycle
# (https://www.nesdev.org/wiki/Cycle_reference_chart). Power-up (plan 12, decision 8) is the CPU's and the PPU's reset;
# "The PPU comes out of power and reset at the top of the picture" (https://www.nesdev.org/wiki/PPU_power_up_state), and
# then catches up the 7 cycles of the CPU's reset sequence, which nestest.log shows as `PPU:  0, 21` at `CYC:7`. The PPU
# ignores writes to PPUCTRL, PPUMASK, PPUSCROLL and PPUADDR until the end of its first VBlank. A frame is 262 scanlines
# of 341 dots, one dot fewer on odd frames with rendering enabled (https://www.nesdev.org/wiki/PPU_frame_timing), and
# ends when the PPU wraps to dot 0 of scanline 0 (plan 12, decision 7).
RSpec.describe Ruby::Nes::Console do
  describe '.new' do
    context 'when the program only loops' do
      # JMP $8000, forever.
      let(:cartridge) { Cartridges.with_program([0x4C, 0x00, 0x80]) }

      it 'starts the CPU at the reset vector, 7 cycles in' do
        console = described_class.new(cartridge)
        expect(console.cpu).to have_attributes(program_counter: 0x8000, cycles: 7)
      end

      it 'starts the PPU 21 dots into scanline 0' do
        console = described_class.new(cartridge)
        expect(console.ppu).to have_attributes(scanline: 0, dot: 21, frame_number: 0)
      end
    end

    context 'when the program enables NMI once, right away' do
      # LDA #$80 / STA $2000 once, then JMP $8005 forever; the NMI handler counts in $10: INC $10 / RTI.
      let(:cartridge) do
        Cartridges.with_program([0xA9, 0x80, 0x8D, 0x00, 0x20, 0x4C, 0x05, 0x80], interrupt_handler: [0xE6, 0x10, 0x40])
      end

      it 'ignores the write, which comes before the end of the first VBlank' do
        console = described_class.new(cartridge)
        console.run_frame
        console.run_frame
        expect(console.cpu_bus.read(0x0010)).to eq(0x00)
      end
    end
  end

  describe '#step' do
    subject(:console) { described_class.new(cartridge) }

    # NOP.
    let(:cartridge) { Cartridges.with_program([0xEA]) }

    it 'runs one CPU instruction and returns its cycles', :aggregate_failures do
      expect(console.step).to eq(2)
      expect(console.cpu.program_counter).to eq(0x8001)
    end

    it 'catches the PPU up to the CPU' do
      console.step
      expect(console.ppu).to have_attributes(scanline: 0, dot: 27)
    end
  end

  describe '#run_frame' do
    subject(:console) { described_class.new(cartridge) }

    context 'when the program leaves rendering disabled' do
      # JMP $8000, forever.
      let(:cartridge) { Cartridges.with_program([0x4C, 0x00, 0x80]) }

      before { console.run_frame }

      it 'stops within the first instruction of the next frame', :aggregate_failures do
        expect(console.ppu).to have_attributes(frame_number: 1, scanline: 0)
        expect(console.ppu.dot).to be < 9
      end

      it 'runs frames of 89 342 dots' do
        cycles_before = console.cpu.cycles
        dot_before = console.ppu.dot
        console.run_frame
        console.run_frame
        console.run_frame
        dots_run = ((console.cpu.cycles - cycles_before) * 3) - (console.ppu.dot - dot_before)
        expect(dots_run).to eq(3 * 89_342)
      end
    end

    context 'when the program keeps enabling rendering' do
      # LDA #$08, then STA $2001 / JMP $8002 forever: background on.
      let(:cartridge) { Cartridges.with_program([0xA9, 0x08, 0x8D, 0x01, 0x20, 0x4C, 0x02, 0x80]) }

      before { console.run_frame }

      it 'runs an odd frame of 89 341 dots and an even one of 89 342' do
        cycles_before = console.cpu.cycles
        dot_before = console.ppu.dot
        console.run_frame
        console.run_frame
        dots_run = ((console.cpu.cycles - cycles_before) * 3) - (console.ppu.dot - dot_before)
        expect(dots_run).to eq(89_341 + 89_342)
      end
    end

    context 'when the program keeps enabling NMI' do
      # LDA #$80, then STA $2000 / JMP $8002 forever; the NMI handler counts in $10: INC $10 / RTI.
      let(:cartridge) do
        Cartridges.with_program([0xA9, 0x80, 0x8D, 0x00, 0x20, 0x4C, 0x02, 0x80], interrupt_handler: [0xE6, 0x10, 0x40])
      end

      before { console.run_frame }

      it 'takes one NMI per frame once the first VBlank has ended' do
        console.run_frame
        console.run_frame
        expect(console.cpu_bus.read(0x0010)).to eq(0x02)
      end
    end

    context 'when the cartridge is nestest, run from its reset vector', test_rom: Nestest::ROM_PATH do
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(Nestest::ROM_PATH)) }

      before { 10.times { console.run_frame } }

      # The digest of the frame inspected with `rake debug:frame` (plan 13): nestest's text menu.
      it 'draws its menu' do
        expect(Digest::SHA256.hexdigest(console.ppu.frame_buffer.pack('C*')))
          .to eq('5459d329572148703205cf288595cd2908e50593af454c300e9610bac07c15dd')
      end
    end
  end

  describe '#reset' do
    context 'when the program only loops' do
      subject(:console) { described_class.new(cartridge) }

      # NOP / NOP, then JMP $8002 forever.
      let(:cartridge) { Cartridges.with_program([0xEA, 0xEA, 0x4C, 0x02, 0x80]) }

      before do
        console.run_frame
        console.reset
      end

      it 'sends the CPU to the reset vector' do
        expect(console.cpu.program_counter).to eq(0x8000)
      end

      it 'puts the PPU 21 dots into scanline 0 of the same frame', :aggregate_failures do
        expect(console.ppu).to have_attributes(scanline: 0, dot: 21, frame_number: 1)
      end
    end

    context 'when the program enables NMI once, right away' do
      subject(:console) { described_class.new(cartridge) }

      # LDA #$80 / STA $2000 once, then JMP $8005 forever; the NMI handler counts in $10: INC $10 / RTI.
      let(:cartridge) do
        Cartridges.with_program([0xA9, 0x80, 0x8D, 0x00, 0x20, 0x4C, 0x05, 0x80], interrupt_handler: [0xE6, 0x10, 0x40])
      end

      before do
        console.run_frame
        console.run_frame
        console.reset
      end

      it 'ignores the write again until the next VBlank ends' do
        console.run_frame
        console.run_frame
        expect(console.cpu_bus.read(0x0010)).to eq(0x00)
      end
    end
  end
end
