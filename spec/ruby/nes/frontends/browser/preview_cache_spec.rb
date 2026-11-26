# frozen_string_literal: true

require 'fileutils'
require 'stringio'
require 'tmpdir'
require 'ruby/nes/saves'
require 'ruby/nes/frontends/browser'

# The ROM browser's cached previews (plan 37, decision 2): a game's preview state, bytes made by Saves::ConsoleState,
# kept at Saves::Directory#preview_path, named after the ROM's SHA-256, and written atomically (Saves::AtomicFile). It
# is a cache: a preview that cannot be read is as one never made, and one that cannot be written is made again next
# time, so neither stops the menu; both are a warning on the error output. One never made is no warning.
RSpec.describe Ruby::Nes::Frontends::Browser::PreviewCache do
  describe '#read' do
    context 'when the data directory cannot be found' do
      subject(:cache) { described_class.new(directory:, error_output:) }

      let(:directory) { Ruby::Nes::Saves::Directory.new(environment: {}, home: -> { '' }) }
      let(:error_output) { StringIO.new }

      it 'is nil, with a warning', :aggregate_failures do
        expect(cache.read('b870f620')).to be_nil
        expect(error_output.string).to match(/\Aruby-nes: the preview cannot be read: neither XDG_DATA_HOME/)
      end
    end

    context 'when it can be found' do
      subject(:cache) { described_class.new(directory:, error_output:) }

      let(:data_home) { Dir.mktmpdir }
      let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
      let(:error_output) { StringIO.new }

      after { FileUtils.remove_entry(data_home) }

      context 'but the preview was never made' do
        it 'is nil, with no warning', :aggregate_failures do
          expect(cache.read('b870f620')).to be_nil
          expect(error_output.string).to be_empty
        end
      end

      context 'but the preview cannot be read' do
        before { FileUtils.mkdir_p(File.join(data_home, 'ruby-nes', 'previews', 'b870f620.state')) }

        it 'is nil, with a warning', :aggregate_failures do
          expect(cache.read('b870f620')).to be_nil
          expect(error_output.string).to match(/\Aruby-nes: the preview cannot be read: Is a directory/)
        end
      end

      context 'and the preview can be read' do
        before do
          FileUtils.mkdir_p(File.join(data_home, 'ruby-nes', 'previews'))
          File.binwrite(File.join(data_home, 'ruby-nes', 'previews', 'b870f620.state'), "state\xFF".b)
        end

        it 'is its bytes' do
          expect(cache.read('b870f620')).to eq("state\xFF".b)
        end
      end
    end
  end

  describe '#write' do
    context 'when the data directory cannot be found' do
      subject(:cache) { described_class.new(directory:, error_output:) }

      let(:directory) { Ruby::Nes::Saves::Directory.new(environment: {}, home: -> { '' }) }
      let(:error_output) { StringIO.new }

      it 'warns' do
        cache.write('b870f620', 'state')

        expect(error_output.string).to match(/\Aruby-nes: the preview was not saved: neither XDG_DATA_HOME/)
      end
    end

    context 'when it can be found' do
      subject(:cache) { described_class.new(directory:, error_output:) }

      let(:data_home) { Dir.mktmpdir }
      let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }
      let(:error_output) { StringIO.new }

      after { FileUtils.remove_entry(data_home) }

      context 'but the preview cannot be written' do
        before { FileUtils.mkdir_p(File.join(data_home, 'ruby-nes', 'previews', 'b870f620.state', 'in the way')) }

        it 'warns' do
          cache.write('b870f620', 'state')

          expect(error_output.string).to match(/\Aruby-nes: the preview was not saved: /)
        end
      end

      context 'and the preview can be written' do
        it 'keeps its bytes, with no warning', :aggregate_failures do
          cache.write('b870f620', "state\xFF".b)

          expect(File.binread(File.join(data_home, 'ruby-nes', 'previews', 'b870f620.state'))).to eq("state\xFF".b)
          expect(error_output.string).to be_empty
        end
      end
    end
  end
end
