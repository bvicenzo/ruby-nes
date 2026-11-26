# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'ruby/nes/saves'

# A game's save states on disk (plan 35, decision 7): each of the 10 slots, 0 to 9, is `<slot>.state` with
# `<slot>.png`, its picture, beside it, in the folder Saves::Directory gives the ROM. Both are written atomically
# (Saves::AtomicFile), the picture first: a state on disk always is one the player was told was saved. The latest slot
# is the one whose state was written last, so a game starts where the player left it (decision 5).
RSpec.describe Ruby::Nes::Saves::StateFiles do
  describe '#write' do
    subject(:files) { described_class.new(directory:, rom_path: 'roms/Zelda.nes') }

    let(:data_home) { Dir.mktmpdir }
    let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }

    after { FileUtils.remove_entry(data_home) }

    context 'when the game has no states folder yet' do
      it 'creates it and writes the state and its picture', :aggregate_failures do
        files.write(3, state: 'state', picture: 'picture')

        expect(File.binread(File.join(data_home, 'ruby-nes', 'states', 'Zelda', '3.state'))).to eq('state')
        expect(File.binread(File.join(data_home, 'ruby-nes', 'states', 'Zelda', '3.png'))).to eq('picture')
      end
    end

    context 'when the game has a states folder' do
      let(:folder) { File.join(data_home, 'ruby-nes', 'states', 'Zelda') }

      before do
        FileUtils.mkdir_p(folder)
        File.binwrite(File.join(folder, '3.state'), 'older state')
        File.binwrite(File.join(folder, '3.png'), 'older picture')
      end

      context 'but the picture cannot be written' do
        before do
          File.delete(File.join(folder, '3.png'))
          FileUtils.mkdir_p(File.join(folder, '3.png', 'in the way'))
        end

        it 'raises, keeping the older state', :aggregate_failures do
          expect { files.write(3, state: 'state', picture: 'picture') }.to raise_error(SystemCallError)
          expect(File.binread(File.join(folder, '3.state'))).to eq('older state')
        end
      end

      context 'and the picture can be written' do
        it 'replaces the state and its picture', :aggregate_failures do
          files.write(3, state: 'state', picture: 'picture')

          expect(File.binread(File.join(folder, '3.state'))).to eq('state')
          expect(File.binread(File.join(folder, '3.png'))).to eq('picture')
        end
      end
    end
  end

  describe '#read' do
    subject(:files) { described_class.new(directory:, rom_path: 'roms/Zelda.nes') }

    let(:data_home) { Dir.mktmpdir }
    let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
    let(:folder) { File.join(data_home, 'ruby-nes', 'states', 'Zelda') }

    after { FileUtils.remove_entry(data_home) }

    context 'when the slot has no state' do
      it 'is nil' do
        expect(files.read(3)).to be_nil
      end
    end

    context 'when the slot has a state' do
      context 'but it cannot be read' do
        before { FileUtils.mkdir_p(File.join(folder, '3.state')) }

        it 'raises the system error' do
          expect { files.read(3) }.to raise_error(Errno::EISDIR)
        end
      end

      context 'and it can be read' do
        before do
          FileUtils.mkdir_p(folder)
          File.binwrite(File.join(folder, '3.state'), "ruby-nes state\n\x01")
        end

        it 'is its bytes' do
          expect(files.read(3)).to eq("ruby-nes state\n\x01".b)
        end
      end
    end
  end

  describe '#latest_slot' do
    subject(:files) { described_class.new(directory:, rom_path: 'roms/Zelda.nes') }

    let(:data_home) { Dir.mktmpdir }
    let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
    let(:folder) { File.join(data_home, 'ruby-nes', 'states', 'Zelda') }

    after { FileUtils.remove_entry(data_home) }

    context 'when the game has no states folder' do
      it 'is nil' do
        expect(files.latest_slot).to be_nil
      end
    end

    context 'when the game has a states folder' do
      context 'but no state is in it' do
        before do
          FileUtils.mkdir_p(folder)
          File.binwrite(File.join(folder, '4.png'), 'picture')
          File.binwrite(File.join(folder, '10.state'), 'not a slot')
          File.binwrite(File.join(folder, 'notes.state'), 'not a slot')
        end

        it 'is nil' do
          expect(files.latest_slot).to be_nil
        end
      end

      context 'and states are in it' do
        context 'and two were written at the same time' do
          before do
            FileUtils.mkdir_p(folder)
            File.binwrite(File.join(folder, '2.state'), 'state')
            File.binwrite(File.join(folder, '7.state'), 'state')
            File.utime(Time.utc(2026, 11, 25, 12), Time.utc(2026, 11, 25, 12), File.join(folder, '2.state'))
            File.utime(Time.utc(2026, 11, 25, 12), Time.utc(2026, 11, 25, 12), File.join(folder, '7.state'))
          end

          it 'is the lower of their slots' do
            expect(files.latest_slot).to eq(2)
          end
        end

        context 'and one was written last' do
          before do
            FileUtils.mkdir_p(folder)
            File.binwrite(File.join(folder, '2.state'), 'state')
            File.binwrite(File.join(folder, '7.state'), 'state')
            File.binwrite(File.join(folder, '9.state'), 'state')
            File.utime(Time.utc(2026, 11, 25, 12), Time.utc(2026, 11, 25, 12), File.join(folder, '2.state'))
            File.utime(Time.utc(2026, 11, 25, 13), Time.utc(2026, 11, 25, 13), File.join(folder, '7.state'))
            File.utime(Time.utc(2026, 11, 25, 11), Time.utc(2026, 11, 25, 11), File.join(folder, '9.state'))
          end

          it 'is its slot' do
            expect(files.latest_slot).to eq(7)
          end
        end
      end
    end
  end

  describe '#written_slots' do
    subject(:files) { described_class.new(directory:, rom_path: 'roms/Zelda.nes') }

    let(:data_home) { Dir.mktmpdir }
    let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
    let(:folder) { File.join(data_home, 'ruby-nes', 'states', 'Zelda') }

    after { FileUtils.remove_entry(data_home) }

    context 'when the game has no states folder' do
      it 'is empty' do
        expect(files.written_slots).to be_empty
      end
    end

    context 'when the game has a states folder' do
      context 'but no state is in it' do
        before do
          FileUtils.mkdir_p(folder)
          File.binwrite(File.join(folder, '4.png'), 'picture')
          File.binwrite(File.join(folder, '10.state'), 'not a slot')
        end

        it 'is empty' do
          expect(files.written_slots).to be_empty
        end
      end

      context 'and states are in it' do
        before do
          FileUtils.mkdir_p(folder)
          File.binwrite(File.join(folder, '7.state'), 'state')
          File.binwrite(File.join(folder, '2.state'), 'state')
        end

        it 'is their slots, in order' do
          expect(files.written_slots).to eq([2, 7])
        end
      end
    end
  end
end
