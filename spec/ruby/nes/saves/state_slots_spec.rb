# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'ruby/nes/command_line'

# The player's save states in the window (plan 35): ten slots, 0 to 9, the current one picked with the previous and
# next slot keys, wrapping around (decision 3); a game starts on the slot it saved last, or 0 (decision 5). Saving
# writes the console's state with a picture of the frame on screen over the current slot at once (decision 4); loading
# brings the console back to it and drops the audio the frontend queued (decision 8). Every action ends with a message
# for the frontend to show (decision 9); a file that cannot be written or read, or a states folder that cannot be
# found, is also a warning on the error output, and the game goes on. The boundaries are the state's files (bytes, nil
# or a raise), the console's state (bytes, a restore or InvalidState) and the picture encoder.
RSpec.describe Ruby::Nes::Saves::StateSlots do
  # Frontends::Hotkeys keeps its own list, so the frontends need nothing from Saves; an action only one of them knew
  # would raise ArgumentError in `perform` and close the window.
  describe 'ACTIONS' do
    it 'are the state actions the hotkeys ask for, in the same order' do
      expect(described_class::ACTIONS).to eq(Ruby::Nes::Frontends::Hotkeys::STATE_ACTIONS)
    end
  end

  describe '.for' do
    let(:data_home) { Dir.mktmpdir }
    let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
    let(:console) { Ruby::Nes::Console.new(Cartridges.with_program([0x4C, 0x00, 0x80])) }
    let(:picture) { Ruby::Nes::Frontends::Screenshot }
    let(:error_output) { StringIO.new }
    let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, notify: nil) }

    after { FileUtils.remove_entry(data_home) }

    it "gives the slots of the console's game, in the ROM's states folder" do
      slots = described_class.for(console:, directory:, rom_path: 'roms/Loop.nes', picture:, error_output:)
      slots.perform(:save_state, frontend)

      expect(Dir.children(File.join(data_home, 'ruby-nes', 'states', 'Loop'))).to contain_exactly('0.state', '0.png')
    end
  end

  describe '#slot' do
    subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output: StringIO.new) }

    let(:console) { instance_double(Ruby::Nes::Console) }
    let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
    let(:picture) { object_double(Ruby::Nes::Frontends::Screenshot) }

    context 'when no slot has a state' do
      let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: nil) }

      it 'is 0' do
        expect(slots.slot).to eq(0)
      end
    end

    context 'when a slot has the latest state' do
      let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 6) }

      it 'is that slot' do
        expect(slots.slot).to eq(6)
      end
    end
  end

  # The slot the pause menu's slot picker opens on (plan 38): the current slot, or the first when the states folder
  # cannot be found, which the action chosen then reports.
  describe '#current_slot' do
    subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output: StringIO.new) }

    let(:console) { instance_double(Ruby::Nes::Console) }
    let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
    let(:picture) { object_double(Ruby::Nes::Frontends::Screenshot) }

    context 'when the states folder cannot be found' do
      let(:files) { instance_double(Ruby::Nes::Saves::StateFiles) }

      before { allow(files).to receive(:latest_slot).and_raise(Ruby::Nes::Saves::Error, 'no home directory') }

      it 'is 0' do
        expect(slots.current_slot).to eq(0)
      end
    end

    context 'when the states folder is found' do
      let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 6) }

      it 'is the current slot' do
        expect(slots.current_slot).to eq(6)
      end
    end
  end

  # The slot picker of the pause menu (plan 38) makes the slot chosen the current one before it saves or loads there.
  describe '#pick' do
    subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output: StringIO.new) }

    let(:console) { instance_double(Ruby::Nes::Console) }
    let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
    let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 6) }
    let(:picture) { object_double(Ruby::Nes::Frontends::Screenshot) }

    context 'when the slot is not one of the slots' do
      it 'raises ArgumentError naming it' do
        expect { slots.pick(10) }.to raise_error(ArgumentError, /10/)
      end
    end

    context 'when the slot is one of the slots' do
      it 'makes it the current slot' do
        slots.pick(2)

        expect(slots.slot).to eq(2)
      end
    end
  end

  # The slot picker marks the slots that hold a state, and offers only those to load.
  describe '#written_slots' do
    subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output: StringIO.new) }

    let(:console) { instance_double(Ruby::Nes::Console) }
    let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
    let(:picture) { object_double(Ruby::Nes::Frontends::Screenshot) }

    context 'when the states folder cannot be found' do
      let(:files) { instance_double(Ruby::Nes::Saves::StateFiles) }

      before { allow(files).to receive(:written_slots).and_raise(Ruby::Nes::Saves::Error, 'no home directory') }

      it 'is empty' do
        expect(slots.written_slots).to be_empty
      end
    end

    context 'when the states folder is found' do
      let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, written_slots: [1, 4]) }

      it "is the game's slots that hold a state" do
        expect(slots.written_slots).to eq([1, 4])
      end
    end
  end

  # The slot picker shows the picture of the slot in focus (Saves::StatePictures), for as long as it is open.
  describe '#pictures' do
    subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output: StringIO.new) }

    let(:console) { instance_double(Ruby::Nes::Console) }
    let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
    let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, read: nil) }
    let(:picture) { object_double(Ruby::Nes::Frontends::Screenshot) }

    it "gives the pictures of the game's slots, read from its files", :aggregate_failures do
      expect(slots.pictures.picture(3)).to be_nil
      expect(files).to have_received(:read).with(3)
    end
  end

  describe '#perform' do
    let(:frame_buffer) { [0x0F] * 4 }
    let(:console) { instance_double(Ruby::Nes::Console, ppu: instance_double(Ruby::Nes::Ppu, frame_buffer:)) }
    let(:picture) { object_double(Ruby::Nes::Frontends::Screenshot, png: 'picture') }
    let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, notify: nil, discard_audio: nil) }
    let(:error_output) { StringIO.new }

    context 'when the action is not a state action' do
      subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

      let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
      let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 3) }

      it 'raises ArgumentError naming it' do
        expect { slots.perform(:rewind, frontend) }.to raise_error(ArgumentError, /rewind/)
      end
    end

    context 'when the action is a state action' do
      context 'but the states folder cannot be found' do
        subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

        let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
        let(:files) { instance_double(Ruby::Nes::Saves::StateFiles) }

        before do
          allow(files).to receive(:latest_slot).and_raise(Ruby::Nes::Saves::Error, 'no home directory')
          slots.perform(:save_state, frontend)
        end

        it 'tells the player and warns', :aggregate_failures do
          expect(frontend).to have_received(:notify).with('States unavailable: no home directory')
          expect(error_output.string).to eq("ruby-nes: save states are unavailable: no home directory\n")
        end
      end

      context 'and it can be found' do
        context 'and the action is next_slot' do
          context 'and the slot is 9' do
            subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

            let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 9) }

            before { slots.perform(:next_slot, frontend) }

            it 'goes to slot 0', :aggregate_failures do
              expect(slots.slot).to eq(0)
              expect(frontend).to have_received(:notify).with('Slot 0')
            end
          end

          context 'and the slot is below 9' do
            subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

            let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 8) }

            before { slots.perform(:next_slot, frontend) }

            it 'goes to the next slot', :aggregate_failures do
              expect(slots.slot).to eq(9)
              expect(frontend).to have_received(:notify).with('Slot 9')
            end
          end
        end

        context 'and the action is previous_slot' do
          context 'and the slot is 0' do
            subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

            let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: nil) }

            before { slots.perform(:previous_slot, frontend) }

            it 'goes to slot 9', :aggregate_failures do
              expect(slots.slot).to eq(9)
              expect(frontend).to have_received(:notify).with('Slot 9')
            end
          end

          context 'and the slot is above 0' do
            subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

            let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 1) }

            before { slots.perform(:previous_slot, frontend) }

            it 'goes to the previous slot', :aggregate_failures do
              expect(slots.slot).to eq(0)
              expect(frontend).to have_received(:notify).with('Slot 0')
            end
          end
        end

        context 'and the action is save_state' do
          context 'but the files cannot be written' do
            subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

            let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState, encode: 'state') }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 3) }

            before do
              allow(files).to receive(:write).and_raise(Errno::EACCES, '3.state')
              slots.perform(:save_state, frontend)
            end

            it 'tells the player and warns', :aggregate_failures do
              expect(frontend).to have_received(:notify).with('State 3 not saved: Permission denied - 3.state')
              expect(error_output.string).to eq("ruby-nes: state 3 was not saved: Permission denied - 3.state\n")
            end
          end

          context 'and they can be written' do
            subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

            let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState, encode: 'state') }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 3, write: nil) }

            before { slots.perform(:save_state, frontend) }

            it "writes the state and the frame's picture over the slot, and says so", :aggregate_failures do
              expect(picture).to have_received(:png).with(frame_buffer)
              expect(files).to have_received(:write).with(3, state: 'state', picture: 'picture')
              expect(frontend).to have_received(:notify).with('State 3 saved')
            end
          end
        end

        context 'and the action is load_state' do
          context 'but the slot has no state' do
            subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

            let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState, restore: nil) }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 3, read: nil) }

            before { slots.perform(:load_state, frontend) }

            it 'says so, restoring nothing', :aggregate_failures do
              expect(frontend).to have_received(:notify).with('State 3 is empty')
              expect(state).not_to have_received(:restore)
              expect(frontend).not_to have_received(:discard_audio)
            end
          end

          context 'but the state cannot be read' do
            subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

            let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState, restore: nil) }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 3) }

            before do
              allow(files).to receive(:read).and_raise(Errno::EACCES, '3.state')
              slots.perform(:load_state, frontend)
            end

            it 'tells the player and warns, restoring nothing', :aggregate_failures do
              expect(frontend).to have_received(:notify).with('State 3 not loaded: Permission denied - 3.state')
              expect(error_output.string).to eq("ruby-nes: state 3 was not loaded: Permission denied - 3.state\n")
              expect(state).not_to have_received(:restore)
            end
          end

          context 'but the console refuses the state' do
            subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

            let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState) }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 3, read: 'state') }

            before do
              allow(state).to receive(:restore).and_raise(Ruby::Nes::Saves::InvalidState, 'saved from another ROM')
              slots.perform(:load_state, frontend)
            end

            it 'tells the player why, keeping the audio', :aggregate_failures do
              expect(frontend).to have_received(:notify).with('State 3 not loaded: saved from another ROM')
              expect(frontend).not_to have_received(:discard_audio)
            end
          end

          context 'and the console restores the state' do
            subject(:slots) { described_class.new(console:, state:, files:, picture:, error_output:) }

            let(:state) { instance_double(Ruby::Nes::Saves::ConsoleState, restore: nil) }
            let(:files) { instance_double(Ruby::Nes::Saves::StateFiles, latest_slot: 3, read: 'state') }

            before { slots.perform(:load_state, frontend) }

            it 'brings the console back to it, drops the queued audio and says so', :aggregate_failures do
              expect(state).to have_received(:restore).with('state')
              expect(frontend).to have_received(:discard_audio)
              expect(frontend).to have_received(:notify).with('State 3 loaded')
            end
          end
        end
      end
    end
  end
end
