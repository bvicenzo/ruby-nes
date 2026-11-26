# frozen_string_literal: true

require 'ruby/nes/command_line'

# The pause menu over a game in the window (plan 38), which Frontends::Driver opens when the window asks for the menu.
# The menu (Frontends::Pause::Menu) opens over the frame on screen with RESUME, SAVE STATE, LOAD STATE, RESET, BACK TO
# THE LIST (only for a game started from the ROM list) and QUIT, and runs in the window (CommandLine::MenuLoop) until a
# choice is made, which is then done: a slot chosen to save or load becomes the current slot and the game's slots
# (Saves::StateSlots) save or load there, saying so; RESET resets the console; these and RESUME resume the window, so
# the buttons held are kept from the game until let go. BACK TO THE LIST ends the game's screen (Frontends::Base#leave)
# and QUIT the session (Frontends::Base#quit). A window that stops running in the menu has nothing done.
RSpec.describe Ruby::Nes::CommandLine::Pause do
  describe '#open' do
    context 'when the menu opens' do
      context 'and the game was started from the ROM list' do
        subject(:pause) { described_class.new(console:, slots:, back_to_list: true) }

        let(:console) { instance_double(Ruby::Nes::Console, ppu: instance_double(Ruby::Nes::Ppu, frame_buffer: [0x21])) }
        let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots) }
        let(:frontend) { instance_double(Ruby::Nes::Frontends::Base) }
        let(:menu) { instance_double(Ruby::Nes::Frontends::Pause::Menu) }

        before do
          allow(Ruby::Nes::Frontends::Pause::Menu).to receive(:new).and_return(menu)
          allow(Ruby::Nes::CommandLine::MenuLoop).to receive(:run).and_return(nil)
        end

        it 'offers every entry over the frame on screen, back to the list included', :aggregate_failures do
          pause.open(frontend)

          expect(Ruby::Nes::Frontends::Pause::Menu).to have_received(:new).with(
            entries: %i[resume save_state load_state reset back_to_list quit], background: [0x21], slots:
          )
          expect(Ruby::Nes::CommandLine::MenuLoop).to have_received(:run).with(frontend:, menu:)
        end
      end

      context 'and the game was started on its own' do
        subject(:pause) { described_class.new(console:, slots:, back_to_list: false) }

        let(:console) { instance_double(Ruby::Nes::Console, ppu: instance_double(Ruby::Nes::Ppu, frame_buffer: [0x21])) }
        let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots) }
        let(:frontend) { instance_double(Ruby::Nes::Frontends::Base) }
        let(:menu) { instance_double(Ruby::Nes::Frontends::Pause::Menu) }

        before do
          allow(Ruby::Nes::Frontends::Pause::Menu).to receive(:new).and_return(menu)
          allow(Ruby::Nes::CommandLine::MenuLoop).to receive(:run).and_return(nil)
        end

        it 'offers every entry but back to the list' do
          pause.open(frontend)

          expect(Ruby::Nes::Frontends::Pause::Menu).to have_received(:new)
            .with(entries: %i[resume save_state load_state reset quit], background: [0x21], slots:)
        end
      end
    end

    context 'when the window stops running in the menu' do
      subject(:pause) { described_class.new(console:, slots:, back_to_list: true) }

      let(:console) { instance_double(Ruby::Nes::Console, ppu: instance_double(Ruby::Nes::Ppu, frame_buffer: [0x21])) }
      let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots) }
      let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, resume: nil) }

      before do
        allow(Ruby::Nes::Frontends::Pause::Menu).to receive(:new)
        allow(Ruby::Nes::CommandLine::MenuLoop).to receive(:run).and_return(nil)
      end

      it 'does nothing' do
        pause.open(frontend)

        expect(frontend).not_to have_received(:resume)
      end
    end

    context 'when RESUME is chosen' do
      subject(:pause) { described_class.new(console:, slots:, back_to_list: true) }

      let(:console) { instance_double(Ruby::Nes::Console, ppu: instance_double(Ruby::Nes::Ppu, frame_buffer: [0x21])) }
      let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots) }
      let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, resume: nil) }

      before do
        allow(Ruby::Nes::Frontends::Pause::Menu).to receive(:new)
        allow(Ruby::Nes::CommandLine::MenuLoop).to receive(:run).and_return(Ruby::Nes::Frontends::Pause::Choice::RESUME)
      end

      it 'resumes the window' do
        pause.open(frontend)

        expect(frontend).to have_received(:resume)
      end
    end

    context 'when a slot is chosen to save' do
      subject(:pause) { described_class.new(console:, slots:, back_to_list: true) }

      let(:console) { instance_double(Ruby::Nes::Console, ppu: instance_double(Ruby::Nes::Ppu, frame_buffer: [0x21])) }
      let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots) }
      let(:frontend) { instance_double(Ruby::Nes::Frontends::Base) }
      let(:choice) { Ruby::Nes::Frontends::Pause::Choice.new(action: :save_state, slot: 4) }

      before do
        allow(Ruby::Nes::Frontends::Pause::Menu).to receive(:new)
        allow(Ruby::Nes::CommandLine::MenuLoop).to receive(:run).and_return(choice)
      end

      it 'picks it, saves there and resumes the window, in that order' do
        calls = []
        allow(slots).to receive(:pick) { |slot| calls << [:pick, slot] }
        allow(slots).to receive(:perform) { |action, state_frontend| calls << [action, state_frontend] }
        allow(frontend).to receive(:resume) { calls << :resume }
        pause.open(frontend)

        expect(calls).to eq([[:pick, 4], [:save_state, frontend], :resume])
      end
    end

    context 'when a slot is chosen to load' do
      subject(:pause) { described_class.new(console:, slots:, back_to_list: true) }

      let(:console) { instance_double(Ruby::Nes::Console, ppu: instance_double(Ruby::Nes::Ppu, frame_buffer: [0x21])) }
      let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots) }
      let(:frontend) { instance_double(Ruby::Nes::Frontends::Base) }
      let(:choice) { Ruby::Nes::Frontends::Pause::Choice.new(action: :load_state, slot: 7) }

      before do
        allow(Ruby::Nes::Frontends::Pause::Menu).to receive(:new)
        allow(Ruby::Nes::CommandLine::MenuLoop).to receive(:run).and_return(choice)
      end

      it 'picks it, loads it and resumes the window, in that order' do
        calls = []
        allow(slots).to receive(:pick) { |slot| calls << [:pick, slot] }
        allow(slots).to receive(:perform) { |action, state_frontend| calls << [action, state_frontend] }
        allow(frontend).to receive(:resume) { calls << :resume }
        pause.open(frontend)

        expect(calls).to eq([[:pick, 7], [:load_state, frontend], :resume])
      end
    end

    context 'when RESET is chosen' do
      subject(:pause) { described_class.new(console:, slots:, back_to_list: true) }

      let(:console) do
        instance_double(Ruby::Nes::Console, ppu: instance_double(Ruby::Nes::Ppu, frame_buffer: [0x21]), reset: nil)
      end
      let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots) }
      let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, resume: nil) }

      before do
        allow(Ruby::Nes::Frontends::Pause::Menu).to receive(:new)
        allow(Ruby::Nes::CommandLine::MenuLoop).to receive(:run)
          .and_return(Ruby::Nes::Frontends::Pause::Choice.new(action: :reset, slot: nil))
      end

      it 'resets the console and resumes the window', :aggregate_failures do
        pause.open(frontend)

        expect(console).to have_received(:reset)
        expect(frontend).to have_received(:resume)
      end
    end

    context 'when BACK TO THE LIST is chosen' do
      subject(:pause) { described_class.new(console:, slots:, back_to_list: true) }

      let(:console) { instance_double(Ruby::Nes::Console, ppu: instance_double(Ruby::Nes::Ppu, frame_buffer: [0x21])) }
      let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots) }
      let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, leave: nil, resume: nil) }

      before do
        allow(Ruby::Nes::Frontends::Pause::Menu).to receive(:new)
        allow(Ruby::Nes::CommandLine::MenuLoop).to receive(:run)
          .and_return(Ruby::Nes::Frontends::Pause::Choice.new(action: :back_to_list, slot: nil))
      end

      it "ends the game's screen without resuming it", :aggregate_failures do
        pause.open(frontend)

        expect(frontend).to have_received(:leave)
        expect(frontend).not_to have_received(:resume)
      end
    end

    context 'when QUIT is chosen' do
      subject(:pause) { described_class.new(console:, slots:, back_to_list: true) }

      let(:console) { instance_double(Ruby::Nes::Console, ppu: instance_double(Ruby::Nes::Ppu, frame_buffer: [0x21])) }
      let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots) }
      let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, quit: nil, resume: nil) }

      before do
        allow(Ruby::Nes::Frontends::Pause::Menu).to receive(:new)
        allow(Ruby::Nes::CommandLine::MenuLoop).to receive(:run)
          .and_return(Ruby::Nes::Frontends::Pause::Choice.new(action: :quit, slot: nil))
      end

      it 'ends the session without resuming the game', :aggregate_failures do
        pause.open(frontend)

        expect(frontend).to have_received(:quit)
        expect(frontend).not_to have_received(:resume)
      end
    end
  end
end
