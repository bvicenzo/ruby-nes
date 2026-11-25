# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'ruby/nes/command_line'

# `ruby-nes ROM` without --headless (plan 18): the key config is read and checked before any window opens, actions it
# leaves without a key are named on the error output, then the console runs in the window, through Frontends::Driver,
# until the window stops; the window is closed however the run ends. The window is opened by an injected callable (the raylib one by default, CommandLine::RaylibWindow): here a
# stand-in that hands over a stand-in frontend.
#
# The game's battery save (plan 34) is loaded before the window opens, by a Saves::BatteryKeeper the driver tells each
# frame, and written when the run ends, before the window closes; a refused save stops the run before the window opens.
# The keeper decides when to write: here a stand-in, but for a real dump without battery RAM, whose run must leave no
# file in the temporary data directory.
RSpec.describe Ruby::Nes::CommandLine::Window do
  describe '#run' do
    subject(:window) { described_class.new(open_window:, default_config_path:, error_output:, saves_directory:) }

    let(:directory) { Dir.mktmpdir }
    let(:default_config_path) { File.join(directory, 'default.yml') }
    let(:config_path) { File.join(directory, 'keys.yml') }
    let(:options) do
      Ruby::Nes::CommandLine::Options.parse(
        ['game.nes', '--config', config_path, '--scale', '2', '--aspect', '8:7', '--crop-overscan']
      )
    end
    let(:error_output) { StringIO.new }
    let(:saves_directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => directory }) }

    after { FileUtils.remove_entry(directory) }

    context 'when the key config cannot be read' do
      let(:open_window) { instance_double(Proc, call: nil) }
      let(:console) { instance_double(Ruby::Nes::Console) }

      it 'raises, opening no window', :aggregate_failures do
        expect { window.run(console, options, jit_name: 'yjit') }.to raise_error(Errno::ENOENT)
        expect(open_window).not_to have_received(:call)
      end
    end

    context 'when the key config can be read' do
      context 'but it is invalid' do
        let(:open_window) { instance_double(Proc, call: nil) }
        let(:console) { instance_double(Ruby::Nes::Console) }

        before { File.write(config_path, "keys:\n  turbo: t\n") }

        it 'raises InvalidConfig, opening no window', :aggregate_failures do
          expect { window.run(console, options, jit_name: 'yjit') }
            .to raise_error(Ruby::Nes::Frontends::KeyConfig::InvalidConfig, /turbo/)
          expect(open_window).not_to have_received(:call)
        end
      end

      context 'and it is valid' do
        context 'but the battery save is refused' do
          let(:open_window) { instance_double(Proc, call: nil) }
          let(:console) { Ruby::Nes::Console.new(Cartridges.build(battery: true)) }
          let(:battery_keeper) { instance_double(Ruby::Nes::Saves::BatteryKeeper) }

          before do
            File.write(config_path, "keys:\n  pause: space\n")
            allow(Ruby::Nes::Saves::BatteryKeeper).to receive(:for).and_return(battery_keeper)
            allow(battery_keeper).to receive(:load).and_raise(Ruby::Nes::Saves::InvalidSave, 'game.sav has 3 bytes')
          end

          it 'raises InvalidSave, opening no window', :aggregate_failures do
            expect { window.run(console, options, jit_name: 'yjit') }
              .to raise_error(Ruby::Nes::Saves::InvalidSave, 'game.sav has 3 bytes')
            expect(open_window).not_to have_received(:call)
          end
        end

        context 'and the battery save is not refused' do
          context 'but the window cannot be opened' do
            let(:open_window) { instance_double(Proc) }
            let(:console) { instance_double(Ruby::Nes::Console, battery_ram: nil) }

            before do
              File.write(config_path, "keys:\n  pause: space\n")
              allow(open_window).to receive(:call).and_raise(Ruby::Nes::Error, 'the raylib library is missing')
            end

            it 'raises the reason' do
              expect { window.run(console, options, jit_name: 'yjit') }
                .to raise_error(Ruby::Nes::Error, 'the raylib library is missing')
            end
          end

          context 'and the window opens' do
            context 'but the run fails' do
              let(:open_window) { instance_double(Proc, call: frontend) }
              let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, close: nil) }
              let(:console) { instance_double(Ruby::Nes::Console, battery_ram: nil) }

              before do
                File.write(config_path, "keys:\n  pause: space\n")
                allow(frontend).to receive(:running?).and_raise(Ruby::Nes::Error, 'the window crashed')
              end

              it 'closes the window', :aggregate_failures do
                expect { window.run(console, options, jit_name: 'yjit') }.to raise_error(Ruby::Nes::Error)
                expect(frontend).to have_received(:close)
              end
            end

            context 'and the run ends at once' do
              let(:open_window) { instance_double(Proc, call: frontend) }
              let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, running?: false, close: nil) }
              let(:console) { instance_double(Ruby::Nes::Console, battery_ram: nil) }

              context 'and every action has a key' do
                before do
                  config = "keys:\n  pause: space\ngamepad:\n  a: right_trigger_1\ngamepad_mappings: 0300,Pad\n"
                  File.write(config_path, config)
                  window.run(console, options, jit_name: 'zjit')
                end

                it 'opens it with the keys, the gamepad config, the viewport, the JIT and the audio' do
                  expect(open_window).to have_received(:call).with(
                    keys: a_hash_including(pause: ['space'], a: ['x']),
                    gamepad_buttons: a_hash_including(a: ['right_trigger_1'], start: ['middle_right']),
                    gamepad_mappings: '0300,Pad',
                    viewport: an_object_having_attributes(width: 585, height: 448),
                    jit_name: 'zjit',
                    audio: true
                  )
                end

                it 'closes the window' do
                  expect(frontend).to have_received(:close)
                end

                it 'warns about nothing' do
                  expect(error_output.string).to be_empty
                end
              end

              context 'and an action is left without a key' do
                before do
                  File.write(config_path, "keys:\n  a: z\n")
                  window.run(console, options, jit_name: 'zjit')
                end

                it 'warns naming it' do
                  expect(error_output.string).to eq("ruby-nes: no key for b\n")
                end
              end
            end

            context 'and the game plays a frame, then the run ends' do
              let(:open_window) { instance_double(Proc, call: frontend) }
              let(:frontend) do
                instance_double(
                  Ruby::Nes::Frontends::Base,
                  paused?: false,
                  reset_requested?: false,
                  button_states: [0x00, 0x00],
                  queue_audio: nil,
                  present: nil,
                  close: nil
                )
              end

              before do
                File.write(config_path, "keys:\n  pause: space\n")
                allow(frontend).to receive(:running?).and_return(true, false)
              end

              context 'but it is a dump without battery RAM', local_rom: 'Bomberman II (USA).nes' do
                let(:console) do
                  cartridge = Ruby::Nes::Cartridge::Loader.from_file(local_rom_path('Bomberman II (USA).nes'))
                  Ruby::Nes::Console.new(cartridge)
                end

                it 'creates no save file' do
                  window.run(console, options, jit_name: 'yjit')

                  expect(Dir.children(directory)).to eq(['keys.yml'])
                end
              end

              context 'and it has battery RAM' do
                let(:console) { Ruby::Nes::Console.new(Cartridges.build(battery: true)) }

                context 'but the save cannot be written' do
                  let(:battery_keeper) { instance_double(Ruby::Nes::Saves::BatteryKeeper, load: nil, frame_ran: nil) }

                  before do
                    allow(Ruby::Nes::Saves::BatteryKeeper).to receive(:for).and_return(battery_keeper)
                    allow(battery_keeper).to receive(:close).and_raise(Errno::EACCES, 'game.sav')
                  end

                  it 'raises, closing the window', :aggregate_failures do
                    expect { window.run(console, options, jit_name: 'yjit') }.to raise_error(Errno::EACCES)
                    expect(frontend).to have_received(:close)
                  end
                end

                context 'and the save is written' do
                  let(:battery_keeper) do
                    instance_double(Ruby::Nes::Saves::BatteryKeeper, load: nil, frame_ran: nil, close: nil)
                  end

                  before { allow(Ruby::Nes::Saves::BatteryKeeper).to receive(:for).and_return(battery_keeper) }

                  it "keeps the ROM's save in the saves directory, told each frame", :aggregate_failures do
                    window.run(console, options, jit_name: 'yjit')

                    expect(Ruby::Nes::Saves::BatteryKeeper).to have_received(:for)
                      .with(console:, directory: saves_directory, rom_path: 'game.nes', error_output:)
                    expect(battery_keeper).to have_received(:load)
                    expect(battery_keeper).to have_received(:frame_ran).once
                  end

                  it 'writes the save before closing the window' do
                    calls = []
                    allow(battery_keeper).to receive(:close) { calls << :battery_keeper }
                    allow(frontend).to receive(:close) { calls << :frontend }

                    window.run(console, options, jit_name: 'yjit')

                    expect(calls).to eq(%i[battery_keeper frontend])
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
