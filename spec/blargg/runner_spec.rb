# frozen_string_literal: true

# The runner steps a console frame by frame until blargg's status at $6000 reports a result (Blargg::Report). A reset
# request is honoured "delayed by at least 100 msec": 7 frames, since an NTSC frame lasts 29 780.5 CPU cycles of a
# 1.789773 MHz clock, 16.6 ms (https://www.nesdev.org/wiki/Cycle_reference_chart). The synthetic programs write the
# signature $DE $B0 $61 at $6001-$6003; RAM is zero at power, so $00 tells a first boot from a run after the reset.
#
# The real ROMs below are the ones plan 12 must pass (its acceptance criteria, plus the other ppu_vbl_nmi singles that
# pass); every ROM's result, failures included, is in docs/test-roms.md. They take seconds each, so they are tagged
# `slow: true` and run only with SLOW=1 (plan 12, decision 6).
RSpec.describe Blargg::Runner do
  describe '#run' do
    subject(:runner) { described_class.new(console, frame_limit:) }

    let(:console) { Ruby::Nes::Console.new(cartridge) }

    context 'when the program never writes the signature' do
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

    context 'when the program is a single ROM of instr_test-v5' do
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 01-basics', :slow, test_rom: 'instr_test-v5/rom_singles/01-basics.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/01-basics.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 02-implied', :slow, test_rom: 'instr_test-v5/rom_singles/02-implied.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/02-implied.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 03-immediate', :slow, test_rom: 'instr_test-v5/rom_singles/03-immediate.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/03-immediate.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 04-zero_page', :slow, test_rom: 'instr_test-v5/rom_singles/04-zero_page.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/04-zero_page.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 05-zp_xy', :slow, test_rom: 'instr_test-v5/rom_singles/05-zp_xy.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/05-zp_xy.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 06-absolute', :slow, test_rom: 'instr_test-v5/rom_singles/06-absolute.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/06-absolute.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 07-abs_xy', :slow, test_rom: 'instr_test-v5/rom_singles/07-abs_xy.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/07-abs_xy.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 08-ind_x', :slow, test_rom: 'instr_test-v5/rom_singles/08-ind_x.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/08-ind_x.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 09-ind_y', :slow, test_rom: 'instr_test-v5/rom_singles/09-ind_y.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/09-ind_y.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 10-branches', :slow, test_rom: 'instr_test-v5/rom_singles/10-branches.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/10-branches.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 11-stack', :slow, test_rom: 'instr_test-v5/rom_singles/11-stack.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/11-stack.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 12-jmp_jsr', :slow, test_rom: 'instr_test-v5/rom_singles/12-jmp_jsr.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/12-jmp_jsr.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 13-rts', :slow, test_rom: 'instr_test-v5/rom_singles/13-rts.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/13-rts.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 14-rti', :slow, test_rom: 'instr_test-v5/rom_singles/14-rti.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/14-rti.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 15-brk', :slow, test_rom: 'instr_test-v5/rom_singles/15-brk.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/15-brk.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 16-special', :slow, test_rom: 'instr_test-v5/rom_singles/16-special.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_test-v5/rom_singles/16-special.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end

    context 'when the program is a single ROM of ppu_vbl_nmi' do
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 01-vbl_basics', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/01-vbl_basics.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('ppu_vbl_nmi/rom_singles/01-vbl_basics.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 02-vbl_set_time', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/02-vbl_set_time.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('ppu_vbl_nmi/rom_singles/02-vbl_set_time.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 03-vbl_clear_time', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/03-vbl_clear_time.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('ppu_vbl_nmi/rom_singles/03-vbl_clear_time.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 04-nmi_control', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/04-nmi_control.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('ppu_vbl_nmi/rom_singles/04-nmi_control.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 09-even_odd_frames', :slow, test_rom: 'ppu_vbl_nmi/rom_singles/09-even_odd_frames.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('ppu_vbl_nmi/rom_singles/09-even_odd_frames.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end

    context 'when the program is a single ROM of instr_misc' do
      let(:frame_limit) { Blargg::Runner::FRAME_LIMIT }

      context 'and it is 01-abs_x_wrap', :slow, test_rom: 'instr_misc/rom_singles/01-abs_x_wrap.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_misc/rom_singles/01-abs_x_wrap.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 02-branch_wrap', :slow, test_rom: 'instr_misc/rom_singles/02-branch_wrap.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_misc/rom_singles/02-branch_wrap.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end

      context 'and it is 03-dummy_reads', :slow, test_rom: 'instr_misc/rom_singles/03-dummy_reads.nes' do
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path('instr_misc/rom_singles/03-dummy_reads.nes')) }

        it 'passes' do
          expect(runner.run).to have_attributes(state: :finished, code: 0x00)
        end
      end
    end
  end
end
