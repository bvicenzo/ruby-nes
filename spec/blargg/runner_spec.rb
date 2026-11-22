# frozen_string_literal: true

# The runner steps a console frame by frame until blargg's status at $6000 reports a result (Blargg::Report). A reset
# request is honoured "delayed by at least 100 msec": 7 frames, since an NTSC frame lasts 29 780.5 CPU cycles of a
# 1.789773 MHz clock, 16.6 ms (https://www.nesdev.org/wiki/Cycle_reference_chart). The synthetic programs write the
# signature $DE $B0 $61 at $6001-$6003; RAM is zero at power, so $00 tells a first boot from a run after the reset.
#
# The real ROMs below are the ones plans 12, 14, 19, 20, 21, 22 and 23 pass: every instr_test-v5 and instr_misc single
# plan 12 covers, instr_test-v5's two multi-test builds (MMC1, plan 20), ppu_vbl_nmi 01-09, sprite_hit_tests_2005.10.05
# 01-11, sprite_overflow_tests 1, 2, 4 and 5, cpu_dummy_reads, mmc3_test_2 1-3 and 5 (MMC3, plan 21), with the APU
# (plan 22) apu_test 1-6, apu_reset, cpu_interrupts_v2's singles and multi-test build, instr_timing 1-2 and instr_misc's
# 04-dummy_reads_apu, and with the DMC (plan 23) apu_test 7-8 and apu_reset's works_immediately; every ROM's result,
# failures included, is in docs/test-roms.md.
# The 2005 suites report through $F8 (Blargg::LegacyReport), 1 meaning passed (a program that reports that way is also
# given its report); cpu_dummy_reads only on screen (Blargg::ScreenReport). Each context's cartridge is the ROM its
# `test_rom:` names. They take seconds each, so they are tagged `slow: true` and run only with SLOW=1 (plan 12, decision
# 6).
RSpec.describe Blargg::Runner do
  describe '#run' do
    subject(:runner) { described_class.new(console, frame_limit:) }

    let(:console) { Ruby::Nes::Console.new(cartridge) }

    context 'when the program never writes the signature' do
      # JMP $8000, forever.
      let(:cartridge) { Cartridges.with_program([0x4C, 0x00, 0x80]) }
      let(:frame_limit) { 30 }

      it 'stops at the frame limit with no result', :aggregate_failures do
        outcome = runner.run
        expect(outcome).to have_attributes(state: :absent, frames: 30)
      end
    end

    context 'when the program keeps running past the frame limit' do
      let(:cartridge) { Cartridges.with_program(Blargg::Programs::KEEPS_RUNNING) }
      let(:frame_limit) { 30 }

      it 'stops at the frame limit with the text so far' do
        expect(runner.run).to have_attributes(state: :running, frames: 30, text: 'A')
      end
    end

    context 'when the program asks for a reset' do
      let(:cartridge) { Cartridges.with_program(Blargg::Programs::REQUESTS_RESET) }
      let(:frame_limit) { 30 }

      it 'presses reset no sooner than 100 ms later, then reports the result', :aggregate_failures do
        outcome = runner.run
        expect(outcome).to have_attributes(state: :finished, code: 0x00)
        expect(outcome.frames).to be >= 9
      end
    end

    context 'when the program still asks for a reset for a while after the reset' do
      let(:cartridge) { Cartridges.with_program(Blargg::Programs::REQUESTS_RESET_THEN_LINGERS) }
      let(:frame_limit) { 30 }

      it 'presses reset only once, then reports the result' do
        expect(runner.run).to have_attributes(state: :finished, code: 0x00)
      end
    end

    context 'when the program finishes' do
      let(:cartridge) { Cartridges.with_program(Blargg::Programs::FINISHES) }
      let(:frame_limit) { 30 }

      it 'reports the result code and the text', :aggregate_failures do
        outcome = runner.run
        expect(outcome).to have_attributes(state: :finished, code: 0x03, text: 'OK')
        expect(outcome.frames).to be < 30
      end
    end

    context 'when the program reports the 2005 way' do
      let(:cartridge) { Cartridges.with_program(Blargg::Programs::LEGACY_FINISHES) }
      let(:frame_limit) { 30 }

      it 'reports the result code once it loops on itself', :aggregate_failures do
        outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
        expect(outcome).to have_attributes(state: :finished, code: 0x01)
        expect(outcome.frames).to be_between(10, 29)
      end
    end

    context 'when the program is a single ROM of instr_test-v5' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 01-basics', :slow, test_rom: 'instr_test-v5/rom_singles/01-basics.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 02-implied', :slow, test_rom: 'instr_test-v5/rom_singles/02-implied.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 03-immediate', :slow, test_rom: 'instr_test-v5/rom_singles/03-immediate.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 04-zero_page', :slow, test_rom: 'instr_test-v5/rom_singles/04-zero_page.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 05-zp_xy', :slow, test_rom: 'instr_test-v5/rom_singles/05-zp_xy.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 06-absolute', :slow, test_rom: 'instr_test-v5/rom_singles/06-absolute.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 07-abs_xy', :slow, test_rom: 'instr_test-v5/rom_singles/07-abs_xy.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 08-ind_x', :slow, test_rom: 'instr_test-v5/rom_singles/08-ind_x.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 09-ind_y', :slow, test_rom: 'instr_test-v5/rom_singles/09-ind_y.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 10-branches', :slow, test_rom: 'instr_test-v5/rom_singles/10-branches.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 11-stack', :slow, test_rom: 'instr_test-v5/rom_singles/11-stack.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 12-jmp_jsr', :slow, test_rom: 'instr_test-v5/rom_singles/12-jmp_jsr.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 13-rts', :slow, test_rom: 'instr_test-v5/rom_singles/13-rts.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 14-rti', :slow, test_rom: 'instr_test-v5/rom_singles/14-rti.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 15-brk', :slow, test_rom: 'instr_test-v5/rom_singles/15-brk.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 16-special', :slow, test_rom: 'instr_test-v5/rom_singles/16-special.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end

    context 'when the program is a multi-test build of instr_test-v5, on an MMC1 board' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is all_instrs', :slow, test_rom: 'instr_test-v5/all_instrs.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is official_only', :slow, test_rom: 'instr_test-v5/official_only.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end

    context 'when the program is a single ROM of ppu_vbl_nmi' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 01-vbl_basics', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/01-vbl_basics.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 02-vbl_set_time', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/02-vbl_set_time.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 03-vbl_clear_time', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/03-vbl_clear_time.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 04-nmi_control', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/04-nmi_control.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 05-nmi_timing', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/05-nmi_timing.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 06-suppression', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/06-suppression.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 07-nmi_on_timing', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/07-nmi_on_timing.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 08-nmi_off_timing', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/08-nmi_off_timing.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 09-even_odd_frames', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/09-even_odd_frames.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end

    context 'when the program is a single ROM of instr_misc' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 01-abs_x_wrap', :slow, test_rom: 'instr_misc/rom_singles/01-abs_x_wrap.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 02-branch_wrap', :slow, test_rom: 'instr_misc/rom_singles/02-branch_wrap.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 03-dummy_reads', :slow, test_rom: 'instr_misc/rom_singles/03-dummy_reads.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 04-dummy_reads_apu', :slow, test_rom: 'instr_misc/rom_singles/04-dummy_reads_apu.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end

    # The APU's length counters and frame counter (plan 22), and the DMC (plan 23).
    context 'when the program is a single ROM of apu_test' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 1-len_ctr', :slow, test_rom: 'apu_test/rom_singles/1-len_ctr.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 2-len_table', :slow, test_rom: 'apu_test/rom_singles/2-len_table.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 3-irq_flag', :slow, test_rom: 'apu_test/rom_singles/3-irq_flag.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 4-jitter', :slow, test_rom: 'apu_test/rom_singles/4-jitter.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 5-len_timing', :slow, test_rom: 'apu_test/rom_singles/5-len_timing.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 6-irq_flag_timing', :slow, test_rom: 'apu_test/rom_singles/6-irq_flag_timing.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 7-dmc_basics', :slow, test_rom: 'apu_test/rom_singles/7-dmc_basics.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 8-dmc_rates', :slow, test_rom: 'apu_test/rom_singles/8-dmc_rates.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end

    # The APU at power and after reset, the runner pressing reset when the program asks (plan 22, decision 4).
    context 'when the program is a ROM of apu_reset' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 4015_cleared', :slow, test_rom: 'apu_reset/4015_cleared.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 4017_timing', :slow, test_rom: 'apu_reset/4017_timing.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 4017_written', :slow, test_rom: 'apu_reset/4017_written.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is irq_flag_cleared', :slow, test_rom: 'apu_reset/irq_flag_cleared.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is len_ctrs_enabled', :slow, test_rom: 'apu_reset/len_ctrs_enabled.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is works_immediately', :slow, test_rom: 'apu_reset/works_immediately.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end

    # The CPU's interrupt timing, timed by the APU's frame IRQ (plan 22, decision 1).
    context 'when the program is a single ROM of cpu_interrupts_v2' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 1-cli_latency', :slow, test_rom: 'cpu_interrupts_v2/rom_singles/1-cli_latency.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 2-nmi_and_brk', :slow, test_rom: 'cpu_interrupts_v2/rom_singles/2-nmi_and_brk.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 3-nmi_and_irq', :slow, test_rom: 'cpu_interrupts_v2/rom_singles/3-nmi_and_irq.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 4-irq_and_dma', :slow, test_rom: 'cpu_interrupts_v2/rom_singles/4-irq_and_dma.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context(
        'and it is 5-branch_delays_irq',
        :slow,
        test_rom: 'cpu_interrupts_v2/rom_singles/5-branch_delays_irq.nes'
      ) do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end

    # The five tests in one MMC1 build (plan 20).
    context 'when the program is a multi-test build of cpu_interrupts_v2, on an MMC1 board' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is cpu_interrupts', :slow, test_rom: 'cpu_interrupts_v2/cpu_interrupts.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end

    # Each instruction timed with the APU's length counter.
    context 'when the program is a single ROM of instr_timing' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 1-instr_timing', :slow, test_rom: 'instr_timing/rom_singles/1-instr_timing.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 2-branch_timing', :slow, test_rom: 'instr_timing/rom_singles/2-branch_timing.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end

    # A CNROM board (plan 19) built with blargg's older shell: its result is only on screen.
    context 'when the program is cpu_dummy_reads', :slow, test_rom: 'cpu_dummy_reads/cpu_dummy_reads.nes' do
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('cpu_dummy_reads/cpu_dummy_reads.nes')) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      it 'passes' do
        outcome = described_class.new(console, frame_limit:, report: Blargg::ScreenReport.new(console)).run
        expect(outcome).to have_attributes(state: :finished, code: Blargg::ScreenReport::PASSED)
      end
    end

    context 'when the program is a single ROM of sprite_hit_tests_2005.10.05' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 01.basics', :slow, test_rom: 'sprite_hit_tests_2005.10.05/01.basics.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 02.alignment', :slow, test_rom: 'sprite_hit_tests_2005.10.05/02.alignment.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 03.corners', :slow, test_rom: 'sprite_hit_tests_2005.10.05/03.corners.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 04.flip', :slow, test_rom: 'sprite_hit_tests_2005.10.05/04.flip.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 05.left_clip', :slow, test_rom: 'sprite_hit_tests_2005.10.05/05.left_clip.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 06.right_edge', :slow, test_rom: 'sprite_hit_tests_2005.10.05/06.right_edge.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 07.screen_bottom', :slow, test_rom: 'sprite_hit_tests_2005.10.05/07.screen_bottom.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 08.double_height', :slow, test_rom: 'sprite_hit_tests_2005.10.05/08.double_height.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 09.timing_basics', :slow, test_rom: 'sprite_hit_tests_2005.10.05/09.timing_basics.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 10.timing_order', :slow, test_rom: 'sprite_hit_tests_2005.10.05/10.timing_order.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 11.edge_timing', :slow, test_rom: 'sprite_hit_tests_2005.10.05/11.edge_timing.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end
    end

    context 'when the program is a single ROM of sprite_overflow_tests' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 1.Basics', :slow, test_rom: 'sprite_overflow_tests/1.Basics.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 2.Details', :slow, test_rom: 'sprite_overflow_tests/2.Details.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 4.Obscure', :slow, test_rom: 'sprite_overflow_tests/4.Obscure.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end

      context 'and it is 5.Emulator', :slow, test_rom: 'sprite_overflow_tests/5.Emulator.nes' do
        it 'passes' do
          outcome = described_class.new(console, frame_limit:, report: Blargg::LegacyReport.new(console)).run
          expect(outcome).to have_attributes(state: :finished, code: Blargg::LegacyReport::PASSED)
        end
      end
    end

    context 'when the program is a single ROM of mmc3_test_2, on an MMC3 board' do
      let(:rom_path) { RSpec.current_example.metadata[:test_rom] }
      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(rom_path)) }
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 1-clocking', :slow, test_rom: 'mmc3_test_2/rom_singles/1-clocking.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 2-details', :slow, test_rom: 'mmc3_test_2/rom_singles/2-details.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 3-A12_clocking', :slow, test_rom: 'mmc3_test_2/rom_singles/3-A12_clocking.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      # The "new" revision's ROM (plan 21, decision 3); 6-MMC3_alt tests the other one.
      context 'and it is 5-MMC3', :slow, test_rom: 'mmc3_test_2/rom_singles/5-MMC3.nes' do
        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end
  end
end
