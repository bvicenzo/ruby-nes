# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'ruby/nes/command_line'

# Keeps a game's battery save in step with the console's battery-backed PRG RAM while the window plays (plan 34): it
# loads the save into the console before the first frame, and writes the RAM back every 300 frames it is told ran
# (decision 4) and when the run ends, each time only when the RAM changed since the load or the last write, so a game
# that never writes its RAM leaves no file (decision 6). A periodic write that fails is a warning and the game goes on;
# the last one, at the end, raises. A console without battery RAM gets Saves::NoBattery, which does nothing, and the
# saves directory is not even asked where its save would be. The save file is the boundary: it reads bytes or nil, or
# refuses its save (Saves::InvalidSave), and writes or raises SystemCallError.
RSpec.describe Ruby::Nes::Saves::BatteryKeeper do
  describe '.for' do
    let(:error_output) { StringIO.new }

    context 'when the console has no battery RAM' do
      let(:console) { Ruby::Nes::Console.new(Cartridges.build(battery: false)) }
      let(:directory) { instance_double(Ruby::Nes::Saves::Directory, battery_save_path: nil) }

      it 'gives NoBattery, asking the directory nothing', :aggregate_failures do
        expect(described_class.for(console:, directory:, rom_path: 'roms/Zelda.nes', error_output:))
          .to eq(Ruby::Nes::Saves::NoBattery)
        expect(directory).not_to have_received(:battery_save_path)
      end
    end

    context 'when it has battery RAM' do
      let(:console) { Ruby::Nes::Console.new(Cartridges.build(battery: true)) }
      let(:data_home) { Dir.mktmpdir }
      let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }

      before do
        FileUtils.mkdir_p(File.join(data_home, 'ruby-nes', 'saves'))
        File.binwrite(File.join(data_home, 'ruby-nes', 'saves', 'Zelda.sav'), "\x11#{"\x00" * 8_191}")
      end

      after { FileUtils.remove_entry(data_home) }

      it "gives a keeper of the save at the ROM's path in the directory" do
        described_class.for(console:, directory:, rom_path: 'roms/Zelda.nes', error_output:).load

        expect(console.battery_ram).to eq([0x11, *Array.new(8_191, 0x00)])
      end
    end
  end

  describe '#load' do
    subject(:keeper) { described_class.new(console:, file:, error_output:) }

    let(:console) { Ruby::Nes::Console.new(Cartridges.build(battery: true)) }
    let(:error_output) { StringIO.new }

    context 'when the file refuses its save' do
      let(:file) { instance_double(Ruby::Nes::Saves::BatteryFile) }

      before { allow(file).to receive(:read).and_raise(Ruby::Nes::Saves::InvalidSave, 'Zelda.sav has 3 bytes') }

      it 'raises it, leaving the RAM untouched', :aggregate_failures do
        expect { keeper.load }.to raise_error(Ruby::Nes::Saves::InvalidSave, 'Zelda.sav has 3 bytes')
        expect(console.battery_ram).to eq(Array.new(8_192, 0x00))
      end
    end

    context 'when the file has no save' do
      let(:file) { instance_double(Ruby::Nes::Saves::BatteryFile, read: nil) }

      it 'leaves the RAM as at power-up' do
        keeper.load

        expect(console.battery_ram).to eq(Array.new(8_192, 0x00))
      end
    end

    context 'when the file has a save' do
      let(:file) { instance_double(Ruby::Nes::Saves::BatteryFile, read: [0x11, *Array.new(8_191, 0x00)]) }

      it "puts it in the console's battery RAM" do
        keeper.load

        expect(console.battery_ram).to eq([0x11, *Array.new(8_191, 0x00)])
      end
    end
  end

  describe '#frame_ran' do
    subject(:keeper) { described_class.new(console:, file:, error_output:) }

    let(:console) { Ruby::Nes::Console.new(Cartridges.build(battery: true)) }
    let(:file) { instance_double(Ruby::Nes::Saves::BatteryFile, read: nil, write: nil) }
    let(:error_output) { StringIO.new }

    before { keeper.load }

    context 'when 299 frames ran' do
      context 'and the RAM changed' do
        before { console.cpu_bus.write(0x6000, 0x11) }

        it 'writes nothing' do
          299.times { keeper.frame_ran }

          expect(file).not_to have_received(:write)
        end
      end
    end

    context 'when the 300th frame runs' do
      context 'but the RAM did not change since the load' do
        it 'writes nothing' do
          300.times { keeper.frame_ran }

          expect(file).not_to have_received(:write)
        end
      end

      context 'and the RAM changed' do
        before { console.cpu_bus.write(0x6000, 0x11) }

        context 'but the save cannot be written' do
          before { allow(file).to receive(:write).and_raise(Errno::ENOSPC, 'Zelda.sav') }

          it 'warns on the error output, without raising' do
            300.times { keeper.frame_ran }

            expect(error_output.string)
              .to eq("ruby-nes: the battery save was not written: No space left on device - Zelda.sav\n")
          end

          it 'tries again 300 frames later' do
            600.times { keeper.frame_ran }

            expect(file).to have_received(:write).twice
          end
        end

        context 'and the save can be written' do
          it 'writes the RAM' do
            300.times { keeper.frame_ran }

            expect(file).to have_received(:write).with([0x11, *Array.new(8_191, 0x00)]).once
          end
        end
      end
    end

    context 'when 300 more frames ran after a write' do
      before do
        console.cpu_bus.write(0x6000, 0x11)
        300.times { keeper.frame_ran }
      end

      context 'but the RAM did not change since that write' do
        it 'writes nothing more' do
          300.times { keeper.frame_ran }

          expect(file).to have_received(:write).once
        end
      end

      context 'and it changed again' do
        before { console.cpu_bus.write(0x6000, 0x22) }

        it 'writes it again' do
          300.times { keeper.frame_ran }

          expect(file).to have_received(:write).with([0x22, *Array.new(8_191, 0x00)]).once
        end
      end
    end
  end

  describe '#close' do
    subject(:keeper) { described_class.new(console:, file:, error_output:) }

    let(:console) { Ruby::Nes::Console.new(Cartridges.build(battery: true)) }
    let(:file) { instance_double(Ruby::Nes::Saves::BatteryFile, read: nil, write: nil) }
    let(:error_output) { StringIO.new }

    before { keeper.load }

    context 'when the RAM did not change since the load' do
      it 'writes nothing' do
        keeper.close

        expect(file).not_to have_received(:write)
      end
    end

    context 'when it did not change since the last write' do
      before do
        console.cpu_bus.write(0x6000, 0x11)
        300.times { keeper.frame_ran }
      end

      it 'writes nothing more' do
        keeper.close

        expect(file).to have_received(:write).once
      end
    end

    context 'when it changed' do
      before { console.cpu_bus.write(0x6000, 0x11) }

      it 'writes the RAM' do
        keeper.close

        expect(file).to have_received(:write).with([0x11, *Array.new(8_191, 0x00)])
      end
    end
  end
end
