# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'ruby/nes/command_line'

# The ROM browser in an open window (plan 37): while the window runs, each frame the menu (Frontends::Browser::Menu, or
# Frontends::Browser::EmptyMenu for a folder with no ROM) is told controller 1's buttons, the window gets a frame of
# silence (so audio keeps pacing it, decision 7; while paused it queues its own) and the menu's picture. A ROM started
# is played (CommandLine::Game) in the same window, on a console of its own, sounding as the options say; the window
# starts over (Frontends::Base#next_screen) on the way in and out. Leaving the game (Escape) returns to the list, read
# again from the folder so its marks are fresh, the focus on the game played; closing the window ends the browser. A
# game that cannot be started, or whose battery save cannot be written as it closes, is a message in the window and a
# warning, and the list comes back. Leaving the list ends the browser.
RSpec.describe Ruby::Nes::CommandLine::Browser do
  describe '#run' do
    context 'when the player leaves the list at once' do
      subject(:browser) do
        described_class.new(frontend:, folder:, roms: [], directory:, audio_sample_rate: nil, error_output:)
      end

      let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, running?: false, present: nil) }
      let(:folder) { '/roms' }
      let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => '/data' }) }
      let(:error_output) { StringIO.new }

      it 'shows nothing' do
        browser.run

        expect(frontend).not_to have_received(:present)
      end
    end

    context 'when the list is shown' do
      context 'but the window is paused' do
        subject(:browser) do
          described_class.new(frontend:, folder:, roms: [], directory:, audio_sample_rate: nil, error_output:)
        end

        let(:frontend) do
          instance_double(
            Ruby::Nes::Frontends::Base, button_states: [0, 0], queue_silence: nil, paused?: true, present: nil
          )
        end
        let(:folder) { '/home/player/roms' }
        let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => '/data' }) }
        let(:error_output) { StringIO.new }

        before { allow(frontend).to receive(:running?).and_return(true, false) }

        it "gives the window the menu's picture, leaving its silence to it", :aggregate_failures do
          browser.run

          expect(frontend).not_to have_received(:queue_silence)
          expect(frontend).to have_received(:present).once
        end
      end

      context 'and the window is not paused' do
        subject(:browser) do
          described_class.new(frontend:, folder:, roms: [], directory:, audio_sample_rate: nil, error_output:)
        end

        let(:frontend) do
          instance_double(
            Ruby::Nes::Frontends::Base, button_states: [0, 0], queue_silence: nil, paused?: false, present: nil
          )
        end
        let(:folder) { '/home/player/roms' }
        let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => '/data' }) }
        let(:error_output) { StringIO.new }

        before { allow(frontend).to receive(:running?).and_return(true, false) }

        it "gives the window a frame of silence and the menu's picture each frame", :aggregate_failures do
          browser.run

          expect(frontend).to have_received(:queue_silence).once
          expect(frontend).to have_received(:present)
            .once
            .with(satisfy { ScreenText.rows(it)[13] == '           NO ROMS IN           ' })
        end
      end
    end

    context 'when the player starts a ROM' do
      let(:start) { Ruby::Nes::Input::Controller::BUTTONS.fetch(:start) }

      context 'but its game cannot be started' do
        subject(:browser) do
          described_class.new(frontend:, folder:, roms:, directory:, audio_sample_rate: nil, error_output:)
        end

        let(:folder) { Dir.mktmpdir }
        let(:data_home) { Dir.mktmpdir }
        let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
        let(:error_output) { StringIO.new }
        # A header that declares 16 KiB of PRG ROM, and nothing after it.
        let(:roms) do
          File.binwrite(File.join(folder, 'Short.nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0))[0, 16])
          Ruby::Nes::Frontends::Browser::RomList.scan(folder, directory:)
        end
        let(:frontend) do
          instance_double(
            Ruby::Nes::Frontends::Base,
            queue_silence: nil,
            paused?: false,
            present: nil,
            notify: nil,
            next_screen: nil,
            closed?: false
          )
        end

        before do
          allow(frontend).to receive(:running?).and_return(true, true, false)
          allow(frontend).to receive(:button_states).and_return([start, 0], [0, 0])
        end

        after do
          FileUtils.remove_entry(folder)
          FileUtils.remove_entry(data_home)
        end

        it 'says why, in the window and as a warning, and shows the list again', :aggregate_failures do
          browser.run

          expect(frontend).to have_received(:notify).with(/16 bytes/)
          expect(error_output.string).to match(/\Aruby-nes: .*16 bytes/)
          expect(frontend).to have_received(:present).once
        end
      end

      context 'and its game starts' do
        context 'but its battery save cannot be written as it closes' do
          subject(:browser) do
            described_class.new(frontend:, folder:, roms:, directory:, audio_sample_rate: nil, error_output:)
          end

          let(:folder) { Dir.mktmpdir }
          let(:data_home) { Dir.mktmpdir }
          let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
          let(:error_output) { StringIO.new }
          let(:roms) do
            File.binwrite(File.join(folder, 'Zelda.nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
            Ruby::Nes::Frontends::Browser::RomList.scan(folder, directory:)
          end
          let(:game) { instance_double(Ruby::Nes::CommandLine::Game, load: nil, play: nil) }
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base,
              queue_silence: nil,
              paused?: false,
              present: nil,
              notify: nil,
              next_screen: nil,
              closed?: false
            )
          end

          before do
            allow(Ruby::Nes::CommandLine::Game).to receive(:new).and_return(game)
            allow(game).to receive(:close).and_raise(Errno::EACCES, 'Zelda.sav')
            allow(frontend).to receive(:running?).and_return(true, true, false)
            allow(frontend).to receive(:button_states).and_return([start, 0], [0, 0])
          end

          after do
            FileUtils.remove_entry(folder)
            FileUtils.remove_entry(data_home)
          end

          it 'says why, in the window and as a warning, and shows the list again', :aggregate_failures do
            browser.run

            expect(frontend).to have_received(:notify).with(/Zelda\.sav/)
            expect(error_output.string).to match(/\Aruby-nes: .*Zelda\.sav/)
            expect(frontend).to have_received(:present).once
          end
        end

        context 'and the player closes the window in it' do
          subject(:browser) do
            described_class.new(frontend:, folder:, roms:, directory:, audio_sample_rate: nil, error_output:)
          end

          let(:folder) { Dir.mktmpdir }
          let(:data_home) { Dir.mktmpdir }
          let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
          let(:error_output) { StringIO.new }
          let(:roms) do
            File.binwrite(File.join(folder, 'Zelda.nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
            Ruby::Nes::Frontends::Browser::RomList.scan(folder, directory:)
          end
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base, button_states: [start, 0], present: nil, next_screen: nil, closed?: true
            )
          end

          before { allow(frontend).to receive(:running?).and_return(true, false) }

          after do
            FileUtils.remove_entry(folder)
            FileUtils.remove_entry(data_home)
          end

          it 'ends, showing the list no more' do
            browser.run

            expect(frontend).not_to have_received(:present)
          end
        end

        context 'and the player leaves it' do
          subject(:browser) do
            described_class.new(frontend:, folder:, roms:, directory:, audio_sample_rate: nil, error_output:)
          end

          let(:folder) { Dir.mktmpdir }
          let(:data_home) { Dir.mktmpdir }
          let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
          let(:error_output) { StringIO.new }
          let(:down) { Ruby::Nes::Input::Controller::BUTTONS.fetch(:down) }
          # Listed before the second game's battery save is there.
          let(:roms) do
            File.binwrite(File.join(folder, 'Castlevania.nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
            File.binwrite(
              File.join(folder, 'Zelda.nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0), battery: true)
            )
            Ruby::Nes::Frontends::Browser::RomList.scan(folder, directory:)
          end
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base,
              queue_silence: nil,
              paused?: false,
              present: nil,
              next_screen: nil,
              closed?: false
            )
          end

          before do
            roms
            FileUtils.mkdir_p(File.join(data_home, 'ruby-nes', 'saves'))
            File.binwrite(File.join(data_home, 'ruby-nes', 'saves', 'Zelda.sav'), "\0" * 8192)
            # Down, then Start: the second game; then, back in the list, one frame.
            allow(frontend).to receive(:running?).and_return(true, true, false, true, false)
            allow(frontend).to receive(:button_states).and_return([down, 0], [start, 0], [0, 0])
          end

          after do
            FileUtils.remove_entry(folder)
            FileUtils.remove_entry(data_home)
          end

          it 'shows the list again, read anew, the focus on the game played', :aggregate_failures do
            browser.run

            expect(frontend).to have_received(:next_screen).twice
            expect(frontend).to have_received(:present)
              .with(satisfy { ScreenText.rows(it)[20] == ' ▶ZELDA                     ♥   ' })
          end
        end
      end
    end
  end
end
