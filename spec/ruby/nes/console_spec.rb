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

    context 'when the board is an MMC1 and the program loads vertical mirroring into Control' do
      # The board times its serial port writes with the CPU's cycles (plan 20, decision 1). LDA #$0E, then five times
      # STA $8000 / LSR A, loading Control with %01110 low bit first, then JMP $8016 forever.
      let(:cartridge) do
        Cartridges.with_program([0xA9, 0x0E, *([0x8D, 0x00, 0x80, 0x4A] * 5), 0x4C, 0x16, 0x80], mapper_number: 1)
      end

      it 'switches the nametables to vertical mirroring' do
        console = described_class.new(cartridge)
        11.times { console.step }
        console.ppu_bus.write(0x2000, 0x77)
        expect(console.ppu_bus.read(0x2400)).to eq(0x00)
      end
    end

    context 'when the board is an MMC3 and the program enables its scanline IRQ with rendering on' do
      # The board takes the CPU as its IRQ line and the PPU as A12's clock, and catches the PPU up before a register
      # write (plan 21). LDA #$40 / STA $4017 (the APU's frame IRQ inhibited, plan 22), LDA #5 / STA $C000 / STA $C001 /
      # STA $E001 / CLI, then LDA #$08 / STA $2000 (sprites at $1000) / LDA #$18 / STA $2001 (background and sprites on)
      # / JMP $8011 forever, as the PPU ignores both until its first VBlank ends. The IRQ handler counts in $10 and
      # acknowledges: INC $10 / STA $E000 / STA $E001 / RTI.
      let(:cartridge) do
        Cartridges.with_program(
          [*inhibit_frame_irq, *enable_irq, *render_forever], interrupt_handler: count_irq, mapper_number: 4
        )
      end
      let(:inhibit_frame_irq) { [0xA9, 0x40, 0x8D, 0x17, 0x40] }
      let(:enable_irq) { [0xA9, 0x05, 0x8D, 0x00, 0xC0, 0x8D, 0x01, 0xC0, 0x8D, 0x01, 0xE0, 0x58] }
      let(:render_forever) { [0xA9, 0x08, 0x8D, 0x00, 0x20, 0xA9, 0x18, 0x8D, 0x01, 0x20, 0x4C, 0x11, 0x80] }
      let(:count_irq) { [0xE6, 0x10, 0x8D, 0x00, 0xE0, 0x8D, 0x01, 0xE0, 0x40] }

      # Rendering starts with the second frame: two rendered frames clock the counter 241 times each (mmc3_test_2's
      # "Counter should be clocked 241 times in PPU frame"), and latch 5 asserts the IRQ every 6 clocks ("N+1"):
      # 482 / 6.
      it 'takes one IRQ every 6 scanline clocks' do
        console = described_class.new(cartridge)
        3.times { console.run_frame }
        expect(console.cpu_bus.read(0x0010)).to eq(80)
      end
    end

    context 'when the program enables interrupts and leaves the APU frame counter as it powers up' do
      # The APU sits in CpuBus's `apu_registers:` slot, is caught up after every step and asserts the frame IRQ on the
      # CPU (plan 22). At power the frame counter runs mode 0 with interrupts allowed ($4017 = $00,
      # https://www.nesdev.org/wiki/CPU_power_up_state), setting the flag every 29830 CPU cycles
      # (https://www.nesdev.org/wiki/APU_Frame_Counter), first 29828 cycles in. CLI, then JMP $8001 forever; the IRQ
      # handler counts in $10 and acknowledges by reading $4015: INC $10 / LDA $4015 / RTI.
      let(:cartridge) do
        Cartridges.with_program([0x58, 0x4C, 0x01, 0x80], interrupt_handler: [0xE6, 0x10, 0xAD, 0x15, 0x40, 0x40])
      end

      # Three frames are about 89 350 CPU cycles: the flag comes at 29828 and 59658, not yet at 89488.
      it 'takes one IRQ per frame counter sequence' do
        console = described_class.new(cartridge)
        3.times { console.run_frame }
        expect(console.cpu_bus.read(0x0010)).to eq(2)
      end
    end

    context 'when the program plays a one-byte DMC sample from the cartridge' do
      # The DMC reads its sample through the CPU bus (plan 23): "Sample address = $C000 + (A * 64)", "Sample length =
      # (L * 16) + 1 bytes" (https://www.nesdev.org/wiki/APU_DMC). $4011 = $40 (level 64), $4010 = $0F (rate 54, no IRQ,
      # no loop), $4012 = $10 ($C400, a NOP, $EA, in the mirrored PRG ROM), $4013 = $00 (1 byte), $4015 = $10, then JMP
      # to itself. $EA's bits from bit 0 are 0 1 0 1 0 1 1 1: -2 +2 -2 +2 -2 +2 +2 +2, so the level ends at 68. The
      # triangle, never clocked, holds its first step's 15; the other channels are silent.
      let(:cartridge) do
        Cartridges.with_program([*set_level_and_rate, *set_address_and_length, *start_sample, *wait_forever])
      end
      let(:set_level_and_rate) { [0xA9, 0x40, 0x8D, 0x11, 0x40, 0xA9, 0x0F, 0x8D, 0x10, 0x40] }
      let(:set_address_and_length) { [0xA9, 0x10, 0x8D, 0x12, 0x40, 0xA9, 0x00, 0x8D, 0x13, 0x40] }
      let(:start_sample) { [0xA9, 0x10, 0x8D, 0x15, 0x40] }
      let(:wait_forever) { [0x4C, 0x19, 0x80] }

      it 'plays the byte read from the cartridge' do
        console = described_class.new(cartridge)
        console.run_frame
        expect(console.apu.output).to eq(Ruby::Nes::Apu::Mixer.mix(0, 0, 15, 0, 68))
      end
    end

    # The controllers (plan 15): a $4016 write of 1 then 0 latches both, and the first read of $4016 reports A of the
    # first controller in bit 0 (https://www.nesdev.org/wiki/Controller_reading). Bits 7-5 repeat the previous read,
    # "usually 010 from the high byte $40" (https://www.nesdev.org/wiki/Open_bus_behavior): the operand of LDA $4016.
    context 'when the program strobes the controllers and reads $4016 into $10' do
      # LDA #$01 / STA $4016 / LDA #$00 / STA $4016 / LDA $4016 / STA $10, then JMP $800F forever.
      let(:cartridge) do
        Cartridges.with_program(
          [0xA9, 0x01, 0x8D, 0x16, 0x40, 0xA9, 0x00, 0x8D, 0x16, 0x40, 0xAD, 0x16, 0x40, 0x85, 0x10, 0x4C, 0x0F, 0x80]
        )
      end

      let(:a_button) { Ruby::Nes::Input::Controller::BUTTONS.fetch(:a) }

      context 'and no button is held' do
        let(:first_controller) { Ruby::Nes::Input::Controller.new }
        let(:second_controller) { Ruby::Nes::Input::Controller.new }

        it 'stores $40' do
          console = described_class.new(cartridge, controllers: [first_controller, second_controller])
          6.times { console.step }
          expect(console.cpu_bus.read(0x0010)).to eq(0x40)
        end
      end

      context 'and A is held on the second controller only' do
        let(:first_controller) { Ruby::Nes::Input::Controller.new }
        let(:second_controller) { Ruby::Nes::Input::Controller.new(buttons: a_button) }

        it 'stores $40' do
          console = described_class.new(cartridge, controllers: [first_controller, second_controller])
          6.times { console.step }
          expect(console.cpu_bus.read(0x0010)).to eq(0x40)
        end
      end

      context 'and A is held on the first controller' do
        let(:first_controller) { Ruby::Nes::Input::Controller.new(buttons: a_button) }
        let(:second_controller) { Ruby::Nes::Input::Controller.new }

        it 'stores $41' do
          console = described_class.new(cartridge, controllers: [first_controller, second_controller])
          6.times { console.step }
          expect(console.cpu_bus.read(0x0010)).to eq(0x41)
        end
      end
    end
  end

  # The frontend sets the buttons held through the controllers (plan 15, decision 6).
  describe '#controllers' do
    let(:cartridge) { Cartridges.with_program([0x4C, 0x00, 0x80]) }

    context 'with the controllers given' do
      let(:first_controller) { Ruby::Nes::Input::Controller.new }
      let(:second_controller) { Ruby::Nes::Input::Controller.new }

      it 'returns them in port order, frozen', :aggregate_failures do
        console = described_class.new(cartridge, controllers: [first_controller, second_controller])
        expect(console.controllers).to match([be(first_controller), be(second_controller)])
        expect(console.controllers).to be_frozen
      end

      it 'leaves the given array unfrozen' do
        given_controllers = [first_controller, second_controller]
        described_class.new(cartridge, controllers: given_controllers)
        expect(given_controllers).not_to be_frozen
      end
    end

    context 'without controllers given' do
      it 'returns two controllers of their own', :aggregate_failures do
        console = described_class.new(cartridge)
        expect(console.controllers).to match([an_instance_of(Ruby::Nes::Input::Controller)] * 2)
        expect(console.controllers.first).not_to be(console.controllers.last)
      end
    end
  end

  # Tooling reads the nametables and pattern tables through it, as it reads the CPU's memory through #cpu_bus.
  describe '#ppu_bus' do
    subject(:console) { described_class.new(cartridge) }

    let(:cartridge) { Cartridges.build(chr_rom: [0x33, *Array.new(8_191, 0x00)]) }

    it "reaches the cartridge's pattern tables" do
      expect(console.ppu_bus.read(0x0000)).to eq(0x33)
    end
  end

  describe '#step' do
    context 'when the instruction is a NOP' do
      subject(:console) { described_class.new(cartridge) }

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

    # The APU catches up after the CPU's step, and a DMC reload on the way halts the CPU 4 cycles (plan 23, decision 2):
    # the step's cycles count them. $4010 = $0F (rate 54), $4013 = $01 (17 bytes), $4015 = $10, then JMP to itself.
    context 'when the program plays a DMC sample' do
      subject(:console) { described_class.new(cartridge) }

      let(:cartridge) { Cartridges.with_program([*set_rate_and_length, *start_sample, *wait_forever]) }
      let(:set_rate_and_length) { [0xA9, 0x0F, 0x8D, 0x10, 0x40, 0xA9, 0x01, 0x8D, 0x13, 0x40] }
      let(:start_sample) { [0xA9, 0x10, 0x8D, 0x15, 0x40] }
      let(:wait_forever) { [0x4C, 0x0F, 0x80] }

      it "returns cycles that add up to the CPU's count, stalls included" do
        cycles_before = console.cpu.cycles
        step_cycles = Array.new(3000) { console.step }.sum
        expect(step_cycles).to eq(console.cpu.cycles - cycles_before)
      end
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

      # The digest of the frame inspected in plan 13, nestest's text menu, over 16-bit pixels as the headless frontend
      # hashes them (plan 16, decision 6): `exe/ruby-nes ROM --headless --frames 10` prints the same one, and
      # `--screenshot 10:menu.png` shows the frame.
      it 'draws its menu' do
        expect(Digest::SHA256.hexdigest(console.ppu.frame_buffer.pack('S<*')))
          .to eq('7ec33df3f7ab4bd0ad88bf4d809d2c9a4ad88993b294a12d55b8e569d4f8610e')
      end
    end

    context 'when the cartridge is Super Mario Bros. 3, played into world 1-1', :slow, local_rom: 'smb3.nes' do
      # The game splits the screen with MMC3's scanline IRQ: the playfield scrolls above, the status bar stays still
      # below; wrong IRQ timing shakes or tears the bar (plan 21). The input (spec/fixtures/smb3_world_1_1.yml) reaches
      # world 1-1 and walks right from frame 1200, so through frames 1300-1399 the playfield scrolls. The status bar
      # fills rows 196-239; the only pixels there that change meanwhile are the timer's ones digit, columns 152-159 of
      # rows 212-217, as the time runs out.
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(local_rom_path('smb3.nes')) }
      let(:input_script_path) { File.expand_path('../../fixtures/smb3_world_1_1.yml', __dir__) }
      let(:input_script) { Ruby::Nes::Frontends::InputScript.parse(File.read(input_script_path)) }
      let(:scrolling_frames) { ScriptedPlay.new(console, input_script).frames(1300..1399) }
      let(:status_bar) { FrameRegion.new(rows: 196..239, hole_rows: 212..217, hole_columns: 152..159) }
      let(:playfield) { FrameRegion.new(rows: 0..195) }

      it 'keeps the status bar still while the playfield scrolls', :aggregate_failures do
        expect(scrolling_frames.map { status_bar.pixels(it) }.uniq.size).to eq(1)
        expect(scrolling_frames.map { playfield.pixels(it) }.uniq.size).to eq(100)
      end
    end
  end

  describe '#audio_samples' do
    let(:cartridge) { Cartridges.with_program([0x4C, 0x00, 0x80]) }

    context 'when the console was built without a sample rate' do
      subject(:console) { described_class.new(cartridge) }

      it 'returns no samples' do
        console.run_frame

        expect(console.audio_samples).to eq([])
      end
    end

    context 'when the console was built with a sample rate' do
      subject(:console) { described_class.new(cartridge, audio_sample_rate: 48_000) }

      # 48 000 samples per second at "60.0988 Hz" (https://www.nesdev.org/wiki/Cycle_reference_chart): 798.7 per frame.
      it 'returns the signed 16-bit samples of the frames run since the last call', :aggregate_failures do
        frames = Array.new(60) do
          console.run_frame
          console.audio_samples
        end
        samples = frames.flatten

        expect(samples.size).to be_within(2).of(47_922)
        expect(samples).to all(be_an(Integer).and(be_between(-32_768, 32_767)))
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

    # "Power-up and reset have the effect of writing $00" to $4015 (https://www.nesdev.org/wiki/APU), which forces the
    # length counters to 0 (https://www.nesdev.org/wiki/APU_Length_Counter).
    context 'when the program enables pulse 1 and loads its length counter' do
      subject(:console) { described_class.new(cartridge) }

      # LDA #$01 / STA $4015 / LDA #$F8 / STA $4003 (entry 31, 30 half frames), then JMP $800A forever.
      let(:cartridge) do
        Cartridges.with_program([0xA9, 0x01, 0x8D, 0x15, 0x40, 0xA9, 0xF8, 0x8D, 0x03, 0x40, 0x4C, 0x0A, 0x80])
      end

      before do
        5.times { console.step }
        console.reset
      end

      it 'silences pulse 1' do
        expect(console.cpu_bus.read(0x4015)).to eq(0x00)
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
