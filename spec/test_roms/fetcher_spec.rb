# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'tmpdir'

RSpec.describe TestRoms::Fetcher do
  describe '#fetch' do
    subject(:fetcher) { described_class.new(entries:, directory:, sources:) }

    let(:directory) { Dir.mktmpdir }
    let(:sources) { instance_double(TestRoms::Sources) }
    let(:rom_content) { "\x4E\x45\x53\x1A\x01".b }
    let(:nestest_rom) do
      TestRoms::Entry.new(path: 'other/nestest.nes', checksum: Digest::SHA256.hexdigest(rom_content))
    end
    let(:rom_file_path) { File.join(directory, 'other/nestest.nes') }
    let(:fetch_error) { TestRoms::FetchError.new('No source delivered other/nestest.nes') }

    after { FileUtils.remove_entry(directory) }

    context 'when the local file is intact' do
      let(:entries) { [nestest_rom] }

      before do
        FileUtils.mkdir_p(File.dirname(rom_file_path))
        File.binwrite(rom_file_path, rom_content)
        allow(sources).to receive(:content_for)
      end

      it 'reports it up to date without asking any source', :aggregate_failures do
        expect { |reporter| fetcher.fetch(&reporter) }.to yield_with_args('other/nestest.nes', :up_to_date)
        expect(sources).not_to have_received(:content_for)
      end
    end

    context 'when the local file is missing' do
      let(:entries) { [nestest_rom] }

      context 'but no source delivers it' do
        before { allow(sources).to receive(:content_for).with(nestest_rom).and_raise(fetch_error) }

        it { expect { fetcher.fetch }.to raise_error(fetch_error) }

        it 'leaves no file behind', :aggregate_failures do
          expect { fetcher.fetch }.to raise_error(TestRoms::FetchError)

          expect(Dir.glob('**/*', base: directory)).to be_empty
        end
      end

      context 'and a source delivers it' do
        before { allow(sources).to receive(:content_for).with(nestest_rom).and_return(rom_content) }

        context 'but writing it fails' do
          before { allow(File).to receive(:rename).and_raise(Errno::ENOSPC) }

          it 'raises the write error and leaves no partial file behind', :aggregate_failures do
            expect { fetcher.fetch }.to raise_error(Errno::ENOSPC)

            expect(Dir.glob('**/*', base: directory)).to eq(['other'])
          end
        end

        context 'and writing it succeeds' do
          it 'writes it, creating its directories, and reports it downloaded', :aggregate_failures do
            expect { |reporter| fetcher.fetch(&reporter) }.to yield_with_args('other/nestest.nes', :downloaded)
            expect(File.binread(rom_file_path)).to eq(rom_content)
          end
        end
      end
    end

    context 'when the local file is corrupted' do
      let(:entries) { [nestest_rom] }
      let(:corrupted_content) { "\x4E\x45\x53".b }

      before do
        FileUtils.mkdir_p(File.dirname(rom_file_path))
        File.binwrite(rom_file_path, corrupted_content)
      end

      context 'but no source delivers it' do
        before { allow(sources).to receive(:content_for).with(nestest_rom).and_raise(fetch_error) }

        it { expect { fetcher.fetch }.to raise_error(fetch_error) }

        it 'leaves the corrupted file untouched', :aggregate_failures do
          expect { fetcher.fetch }.to raise_error(TestRoms::FetchError)

          expect(File.binread(rom_file_path)).to eq(corrupted_content)
          expect(Dir.children(File.dirname(rom_file_path))).to eq(['nestest.nes'])
        end
      end

      context 'and a source delivers it' do
        before { allow(sources).to receive(:content_for).with(nestest_rom).and_return(rom_content) }

        it 'replaces it and reports it downloaded', :aggregate_failures do
          expect { |reporter| fetcher.fetch(&reporter) }.to yield_with_args('other/nestest.nes', :downloaded)
          expect(File.binread(rom_file_path)).to eq(rom_content)
        end
      end
    end

    context 'when there are several files' do
      let(:entries) { [nestest_rom, nestest_log, instructions_rom] }
      let(:log_content) { "C000  4C F5 C5  JMP $C5F5\n" }
      let(:nestest_log) do
        TestRoms::Entry.new(path: 'other/nestest.log', checksum: Digest::SHA256.hexdigest(log_content))
      end
      let(:instructions_rom) do
        TestRoms::Entry.new(path: 'instr_test-v5/official_only.nes', checksum: Digest::SHA256.hexdigest('instructions'))
      end

      before do
        FileUtils.mkdir_p(File.dirname(rom_file_path))
        File.binwrite(rom_file_path, rom_content)
      end

      context 'but one of them cannot be delivered' do
        before do
          allow(sources).to receive(:content_for).with(nestest_log).and_raise(fetch_error)
          allow(sources).to receive(:content_for).with(instructions_rom)
        end

        it 'reports the files before it, then stops before the files after it', :aggregate_failures do
          reported_outcomes = []

          expect { fetcher.fetch { |path, outcome| reported_outcomes << [path, outcome] } }.to raise_error(fetch_error)
          expect(reported_outcomes).to eq([['other/nestest.nes', :up_to_date]])
          expect(sources).not_to have_received(:content_for).with(instructions_rom)
        end
      end

      context 'and each one is intact or delivered' do
        before do
          allow(sources).to receive(:content_for).with(nestest_log).and_return(log_content)
          allow(sources).to receive(:content_for).with(instructions_rom).and_return('instructions')
        end

        it 'reports each file under its outcome, in manifest order' do
          expect { |reporter| fetcher.fetch(&reporter) }.to yield_successive_args(
            ['other/nestest.nes', :up_to_date],
            ['other/nestest.log', :downloaded],
            ['instr_test-v5/official_only.nes', :downloaded]
          )
        end
      end
    end
  end
end
