# frozen_string_literal: true

require 'ruby/nes/command_line'

# Where ruby-nes keeps what it saves (plan 34, decision 1): the user's data directory of the XDG Base Directory
# Specification (https://specifications.freedesktop.org/basedir/latest/), "If $XDG_DATA_HOME is either not set or
# empty, a default equal to $HOME/.local/share should be used", and a relative path there is "invalid" and ignored.
# The home directory is Ruby's (Dir.home: HOME, else the user's account), as for the key config's `~`, and must be an
# absolute path. A battery save is named after the ROM's file name (plan 34, decision 2).
RSpec.describe Ruby::Nes::Saves::Directory do
  describe '#root' do
    context 'when XDG_DATA_HOME is not set' do
      context 'but the home directory is not an absolute path' do
        subject(:directory) { described_class.new(environment: {}, home: -> { '' }) }

        it 'raises Saves::Error naming both' do
          expect { directory.root }.to raise_error(Ruby::Nes::Saves::Error, /XDG_DATA_HOME.*home/)
        end
      end

      context 'and the home directory is an absolute path' do
        subject(:directory) { described_class.new(environment: {}, home: -> { '/home/player' }) }

        it 'is ruby-nes under its .local/share' do
          expect(directory.root).to eq('/home/player/.local/share/ruby-nes')
        end
      end
    end

    context 'when XDG_DATA_HOME is empty' do
      subject(:directory) { described_class.new(environment: { 'XDG_DATA_HOME' => '' }, home: -> { '/home/player' }) }

      it 'is ruby-nes under the home directory\'s .local/share' do
        expect(directory.root).to eq('/home/player/.local/share/ruby-nes')
      end
    end

    context 'when XDG_DATA_HOME is a relative path' do
      subject(:directory) do
        described_class.new(environment: { 'XDG_DATA_HOME' => 'data' }, home: -> { '/home/player' })
      end

      it 'is ruby-nes under the home directory\'s .local/share' do
        expect(directory.root).to eq('/home/player/.local/share/ruby-nes')
      end
    end

    context 'when XDG_DATA_HOME is an absolute path' do
      subject(:directory) { described_class.new(environment: { 'XDG_DATA_HOME' => '/data' }, home: -> { '' }) }

      it 'is ruby-nes under XDG_DATA_HOME, whatever the home directory' do
        expect(directory.root).to eq('/data/ruby-nes')
      end
    end
  end

  describe '#battery_save_path' do
    subject(:directory) { described_class.new(environment: { 'XDG_DATA_HOME' => '/data' }, home: -> { '' }) }

    context 'when the ROM is a .nes file in a folder' do
      it 'is the ROM name with .sav in the saves folder of the root' do
        expect(directory.battery_save_path('roms/Zelda.nes')).to eq('/data/ruby-nes/saves/Zelda.sav')
      end
    end

    context 'when the ROM name has dots of its own' do
      it 'replaces only the extension' do
        expect(directory.battery_save_path('Mario Bros. 3.nes')).to eq('/data/ruby-nes/saves/Mario Bros. 3.sav')
      end
    end

    context 'when the extension is upper case' do
      it 'replaces it with .sav' do
        expect(directory.battery_save_path('ZELDA.NES')).to eq('/data/ruby-nes/saves/ZELDA.sav')
      end
    end

    context 'when the ROM file has no extension' do
      it 'appends .sav' do
        expect(directory.battery_save_path('zelda')).to eq('/data/ruby-nes/saves/zelda.sav')
      end
    end
  end

  # Each game's save states live in a folder named after the ROM file, as its battery save is (plan 35, decision 7).
  describe '#states_folder' do
    subject(:directory) { described_class.new(environment: { 'XDG_DATA_HOME' => '/data' }, home: -> { '' }) }

    context 'when the ROM is a .nes file in a folder' do
      it 'is the ROM name in the states folder of the root' do
        expect(directory.states_folder('roms/Zelda.nes')).to eq('/data/ruby-nes/states/Zelda')
      end
    end

    context 'when the ROM name has dots of its own' do
      it 'leaves out only the extension' do
        expect(directory.states_folder('Mario Bros. 3.nes')).to eq('/data/ruby-nes/states/Mario Bros. 3')
      end
    end

    context 'when the extension is upper case' do
      it 'leaves it out' do
        expect(directory.states_folder('ZELDA.NES')).to eq('/data/ruby-nes/states/ZELDA')
      end
    end

    context 'when the ROM file has no extension' do
      it 'is the whole name' do
        expect(directory.states_folder('zelda')).to eq('/data/ruby-nes/states/zelda')
      end
    end
  end
end
