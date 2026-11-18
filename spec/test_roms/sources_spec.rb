# frozen_string_literal: true

require 'digest'

RSpec.describe TestRoms::Sources do
  describe '#content_for' do
    subject(:sources) { described_class.new(manifest:, downloader:) }

    let(:rom_content) { "\x4E\x45\x53\x1A\x01".b }
    let(:nestest) { TestRoms::Entry.new(path: 'other/nestest.nes', checksum: Digest::SHA256.hexdigest(rom_content)) }
    let(:upstream_url) { 'https://upstream.example/roms/95d8f621/other/nestest.nes' }
    let(:mirror_url) { 'https://mirror.example/roms/95d8f621/other/nestest.nes' }
    let(:downloader) { instance_double(TestRoms::Downloader) }
    let(:source_list) { ['https://upstream.example/roms', 'https://mirror.example/roms'] }
    let(:manifest) { TestRoms::Manifest.new(commit: '95d8f621', sources: source_list, entries: [nestest]) }

    context 'when no source delivers matching content' do
      before do
        allow(downloader)
          .to receive(:get).with(upstream_url).and_raise(TestRoms::DownloadError, "#{upstream_url} answered 404")
        allow(downloader).to receive(:get).with(mirror_url).and_return("\x4E\x45\x53\x1A\x02".b)
      end

      it 'raises a FetchError naming the file and the reason of every source' do
        every_source_reason = %r{other/nestest\.nes.*answered 404.*#{Regexp.escape(mirror_url)} .*checksum}m

        expect { sources.content_for(nestest) }.to raise_error(TestRoms::FetchError, every_source_reason)
      end
    end

    context 'when a later source delivers matching content' do
      before { allow(downloader).to receive(:get).with(mirror_url).and_return(rom_content) }

      context 'and the first one could not be downloaded' do
        before do
          allow(downloader).to receive(:get).with(upstream_url).and_raise(TestRoms::DownloadError, 'unreachable')
        end

        it { expect(sources.content_for(nestest)).to eq(rom_content) }
      end

      context 'and the first one delivered content that does not match' do
        before { allow(downloader).to receive(:get).with(upstream_url).and_return("\x4E\x45\x53\x1A\x02".b) }

        it { expect(sources.content_for(nestest)).to eq(rom_content) }
      end
    end

    context 'when the first source delivers matching content' do
      before { allow(downloader).to receive(:get).with(upstream_url).and_return(rom_content) }

      it 'returns its content without asking the other sources', :aggregate_failures do
        expect(sources.content_for(nestest)).to eq(rom_content)
        expect(downloader).to have_received(:get).once
      end
    end
  end
end
