# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'ruby/nes/command_line'

# A game played in an open window (plan 37, out of CommandLine::Window): its battery save (plan 34) is loaded first,
# kept by a Saves::BatteryKeeper the driver tells each frame (Frontends::Driver), and written when the game is closed,
# however it ends; a refused save is never written over. Its save states (plan 35) are kept by a Saves::StateSlots the
# driver hands each state action the frontend asks for, and which its pause menu (CommandLine::Pause, plan 38) saves and
# loads through; the menu offers BACK TO THE LIST only for a game started from the ROM list. The keeper decides when to
# write: here a stand-in, but for a real dump without battery RAM, whose game must leave no file in the temporary data
# directory.
RSpec.describe Ruby::Nes::CommandLine::Game do
  describe '#load' do
    context 'when the battery save is refused' do
      subject(:game) do
        described_class.new(console:, rom_path: 'roms/game.nes', directory: saves_directory, error_output:)
      end

      let(:data_home) { Dir.mktmpdir }
      let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
      let(:error_output) { StringIO.new }
      let(:console) { Ruby::Nes::Console.new(Cartridges.build(battery: true)) }

      before do
        FileUtils.mkdir_p(File.join(data_home, 'ruby-nes', 'saves'))
        File.binwrite(File.join(data_home, 'ruby-nes', 'saves', 'game.sav'), 'abc')
      end

      after { FileUtils.remove_entry(data_home) }

      it 'raises InvalidSave' do
        expect { game.load }.to raise_error(Ruby::Nes::Saves::InvalidSave)
      end
    end

    context 'when it is not' do
      subject(:game) do
        described_class.new(console:, rom_path: 'roms/game.nes', directory: saves_directory, error_output:)
      end

      let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => '/data' }) }
      let(:error_output) { StringIO.new }
      let(:console) { instance_double(Ruby::Nes::Console) }
      let(:battery_keeper) { instance_double(Ruby::Nes::Saves::BatteryKeeper, load: nil) }

      before { allow(Ruby::Nes::Saves::BatteryKeeper).to receive(:for).and_return(battery_keeper) }

      it "puts the ROM's save from the saves directory into the console", :aggregate_failures do
        game.load

        expect(Ruby::Nes::Saves::BatteryKeeper).to have_received(:for)
          .with(console:, directory: saves_directory, rom_path: 'roms/game.nes', error_output:)
        expect(battery_keeper).to have_received(:load)
      end
    end
  end

  describe '#play' do
    context 'when the game plays a frame' do
      context 'and the player saves a state before it' do
        subject(:game) do
          described_class.new(console:, rom_path: 'roms/game.nes', directory: saves_directory, error_output:)
        end

        let(:data_home) { Dir.mktmpdir }
        let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
        let(:error_output) { StringIO.new }
        let(:console) { Ruby::Nes::Console.new(Cartridges.build) }
        let(:frontend) do
          instance_double(
            Ruby::Nes::Frontends::Base,
            menu_requested?: false,
            paused?: false,
            reset_requested?: false,
            notify: nil,
            button_states: [0x00, 0x00],
            queue_audio: nil,
            present: nil
          )
        end

        before do
          allow(frontend).to receive(:running?).and_return(true, false)
          allow(frontend).to receive(:state_action).and_return(:save_state, nil)
          game.load
        end

        after { FileUtils.remove_entry(data_home) }

        it "saves it with its picture in the ROM's states folder, and says so", :aggregate_failures do
          game.play(frontend)

          expect(Dir.children(File.join(data_home, 'ruby-nes', 'states', 'game')))
            .to contain_exactly('0.state', '0.png')
          expect(frontend).to have_received(:notify).with('State 0 saved')
        end
      end

      context 'and the game has battery RAM' do
        subject(:game) do
          described_class.new(console:, rom_path: 'roms/game.nes', directory: saves_directory, error_output:)
        end

        let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => '/data' }) }
        let(:error_output) { StringIO.new }
        let(:console) { Ruby::Nes::Console.new(Cartridges.build(battery: true)) }
        let(:battery_keeper) { instance_double(Ruby::Nes::Saves::BatteryKeeper, load: nil, frame_ran: nil) }
        let(:frontend) do
          instance_double(
            Ruby::Nes::Frontends::Base,
            menu_requested?: false,
            paused?: false,
            reset_requested?: false,
            state_action: nil,
            button_states: [0x00, 0x00],
            queue_audio: nil,
            present: nil
          )
        end

        before do
          allow(Ruby::Nes::Saves::BatteryKeeper).to receive(:for).and_return(battery_keeper)
          allow(frontend).to receive(:running?).and_return(true, false)
          game.load
        end

        it 'tells the keeper of its save each frame' do
          game.play(frontend)

          expect(battery_keeper).to have_received(:frame_ran).once
        end
      end
    end

    context 'when the player opens the menu' do
      context 'and the game was started from the ROM list' do
        subject(:game) do
          described_class.new(
            console:, rom_path: 'roms/game.nes', directory: saves_directory, error_output:, back_to_list: true
          )
        end

        let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => '/data' }) }
        let(:error_output) { StringIO.new }
        let(:console) { Ruby::Nes::Console.new(Cartridges.build) }
        let(:pause) { instance_double(Ruby::Nes::CommandLine::Pause, open: nil) }
        let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, reset_requested?: false, state_action: nil) }

        before do
          allow(Ruby::Nes::CommandLine::Pause).to receive(:new).and_return(pause)
          allow(frontend).to receive(:menu_requested?).and_return(true)
          allow(frontend).to receive(:running?).and_return(true, false)
          game.load
        end

        it 'opens the pause menu over the game, with its slots and the way back to the list', :aggregate_failures do
          game.play(frontend)

          expect(Ruby::Nes::CommandLine::Pause).to have_received(:new)
            .with(console:, slots: an_instance_of(Ruby::Nes::Saves::StateSlots), back_to_list: true)
          expect(pause).to have_received(:open).with(frontend)
        end
      end

      context 'and the game was started on its own' do
        subject(:game) do
          described_class.new(console:, rom_path: 'roms/game.nes', directory: saves_directory, error_output:)
        end

        let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => '/data' }) }
        let(:error_output) { StringIO.new }
        let(:console) { Ruby::Nes::Console.new(Cartridges.build) }
        let(:pause) { instance_double(Ruby::Nes::CommandLine::Pause, open: nil) }
        let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, reset_requested?: false, state_action: nil) }

        before do
          allow(Ruby::Nes::CommandLine::Pause).to receive(:new).and_return(pause)
          allow(frontend).to receive(:menu_requested?).and_return(true)
          allow(frontend).to receive(:running?).and_return(true, false)
          game.load
        end

        it 'opens the pause menu over the game without the way back to the list' do
          game.play(frontend)

          expect(Ruby::Nes::CommandLine::Pause).to have_received(:new)
            .with(console:, slots: an_instance_of(Ruby::Nes::Saves::StateSlots), back_to_list: false)
        end
      end
    end
  end

  describe '#close' do
    context 'when the save was never loaded' do
      subject(:game) do
        described_class.new(console:, rom_path: 'roms/game.nes', directory: saves_directory, error_output:)
      end

      let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => '/data' }) }
      let(:error_output) { StringIO.new }
      let(:console) { Ruby::Nes::Console.new(Cartridges.build(battery: true)) }
      let(:battery_keeper) { instance_double(Ruby::Nes::Saves::BatteryKeeper, close: nil) }

      before do
        allow(Ruby::Nes::Saves::BatteryKeeper).to receive(:for).and_return(battery_keeper)
        allow(battery_keeper).to receive(:load).and_raise(Ruby::Nes::Saves::InvalidSave, 'game.sav has 3 bytes')
      end

      it 'writes nothing over it', :aggregate_failures do
        expect { game.load }.to raise_error(Ruby::Nes::Saves::InvalidSave)
        game.close

        expect(battery_keeper).not_to have_received(:close)
      end
    end

    context 'when it was loaded' do
      context 'but the dump has no battery RAM', local_rom: 'Bomberman II (USA).nes' do
        subject(:game) do
          described_class.new(console:, rom_path: 'roms/game.nes', directory: saves_directory, error_output:)
        end

        let(:data_home) { Dir.mktmpdir }
        let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
        let(:error_output) { StringIO.new }
        let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(local_rom_path('Bomberman II (USA).nes')) }
        let(:console) { Ruby::Nes::Console.new(cartridge) }
        let(:frontend) do
          instance_double(
            Ruby::Nes::Frontends::Base,
            menu_requested?: false,
            paused?: false,
            reset_requested?: false,
            state_action: nil,
            button_states: [0x00, 0x00],
            queue_audio: nil,
            present: nil
          )
        end

        before do
          allow(frontend).to receive(:running?).and_return(true, false)
          game.load
          game.play(frontend)
        end

        after { FileUtils.remove_entry(data_home) }

        it 'creates no save file' do
          game.close

          expect(Dir.children(data_home)).to be_empty
        end
      end

      context 'and the game has battery RAM' do
        subject(:game) do
          described_class.new(console:, rom_path: 'roms/game.nes', directory: saves_directory, error_output:)
        end

        let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => '/data' }) }
        let(:error_output) { StringIO.new }
        let(:console) { Ruby::Nes::Console.new(Cartridges.build(battery: true)) }
        let(:battery_keeper) { instance_double(Ruby::Nes::Saves::BatteryKeeper, load: nil, close: nil) }

        before do
          allow(Ruby::Nes::Saves::BatteryKeeper).to receive(:for).and_return(battery_keeper)
          game.load
        end

        it 'writes the save' do
          game.close

          expect(battery_keeper).to have_received(:close)
        end
      end
    end
  end
end
