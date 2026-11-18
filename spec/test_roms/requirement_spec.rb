# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'tmpdir'

RSpec.describe TestRoms::Requirement do
  describe '#skip_reason' do
    subject(:requirement) { described_class.new(manifest:, directory:) }

    let(:directory) { Dir.mktmpdir }
    let(:rom_content) { "\x4E\x45\x53\x1A\x01".b }
    let(:log_content) { "C000  4C F5 C5  JMP $C5F5\n" }
    let(:rom_checksum) { Digest::SHA256.hexdigest(rom_content) }
    let(:log_checksum) { Digest::SHA256.hexdigest(log_content) }
    let(:nestest_rom) { TestRoms::Entry.new(path: 'other/nestest.nes', checksum: rom_checksum) }
    let(:nestest_log) { TestRoms::Entry.new(path: 'other/nestest.log', checksum: log_checksum) }
    let(:manifest) do
      TestRoms::Manifest
        .new(commit: '95d8f621', sources: ['https://upstream.example/roms'], entries: [nestest_rom, nestest_log])
    end

    before do
      FileUtils.mkdir_p(File.join(directory, 'other'))
      File.binwrite(File.join(directory, 'other/nestest.nes'), rom_content)
    end

    after { FileUtils.remove_entry(directory) }

    context 'when a declared path is not listed' do
      it 'raises an UnknownRomError naming the path' do
        expect { requirement.skip_reason(['other/nestest.nes', 'other/nestset.log']) }
          .to raise_error(TestRoms::UnknownRomError, %r{other/nestset\.log})
      end
    end

    context 'when every declared path is listed' do
      context 'but some ROMs are missing or corrupted' do
        before { File.write(File.join(directory, 'other/nestest.nes'), 'corrupted') }

        it 'names each of them and the rake task that fetches them' do
          reason = 'Test ROMs missing or corrupted (other/nestest.nes, other/nestest.log): ' \
                   'run `bundle exec rake test_roms:fetch`'

          expect(requirement.skip_reason(['other/nestest.nes', 'other/nestest.log'])).to eq(reason)
        end
      end

      context 'and every ROM is intact' do
        before { File.write(File.join(directory, 'other/nestest.log'), log_content) }

        it { expect(requirement.skip_reason(['other/nestest.nes', 'other/nestest.log'])).to be_nil }
      end
    end
  end

  describe '#ensure_listed' do
    subject(:requirement) { described_class.new(manifest:, directory: '/fixtures/test_roms') }

    let(:nestest_rom) { TestRoms::Entry.new(path: 'other/nestest.nes', checksum: 'aaaa') }
    let(:manifest) do
      TestRoms::Manifest.new(commit: '95d8f621', sources: ['https://upstream.example/roms'], entries: [nestest_rom])
    end

    context 'when a declaration is not a path' do
      it 'raises an UnknownRomError asking for the ROM paths' do
        expect { requirement.ensure_listed([true]) }
          .to raise_error(TestRoms::UnknownRomError, /declare the ROM paths: test_rom: 'path'/)
      end
    end

    context 'when a path is not listed' do
      it 'raises an UnknownRomError naming it' do
        expect { requirement.ensure_listed(['other/nestest.nes', 'other/nestset.log']) }
          .to raise_error(TestRoms::UnknownRomError, %r{other/nestset\.log})
      end
    end

    context 'when every path is listed' do
      it { expect { requirement.ensure_listed(['other/nestest.nes']) }.not_to raise_error }
    end
  end

  describe '#path_of' do
    subject(:requirement) { described_class.new(manifest:, directory: '/fixtures/test_roms') }

    let(:nestest_rom) { TestRoms::Entry.new(path: 'other/nestest.nes', checksum: 'aaaa') }
    let(:manifest) do
      TestRoms::Manifest.new(commit: '95d8f621', sources: ['https://upstream.example/roms'], entries: [nestest_rom])
    end

    context 'when the path is not listed' do
      it { expect { requirement.path_of('other/nestset.nes') }.to raise_error(TestRoms::UnknownRomError) }
    end

    context 'when the path is listed' do
      it { expect(requirement.path_of('other/nestest.nes')).to eq('/fixtures/test_roms/other/nestest.nes') }
    end
  end
end
