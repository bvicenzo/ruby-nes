# frozen_string_literal: true

require 'ruby/nes/frontends/wav'

# WAVE (https://www.mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/WAVE.html): "a master RIFF chunk which includes a
# WAVE identifier followed by sub-chunks", "stored in little-endian byte order". The RIFF chunk's size is "4+n", the
# WAVE ID and the chunks after it. The fmt chunk (size 16 for PCM) holds the format code (1, PCM), the channels, the
# sample rate, the data rate (bytes per second), the block size (bytes per sample frame, for all channels) and the bits
# per sample; the data chunk holds the samples. "PCM data is two's-complement except for resolutions of 1-8 bits".
# Here: mono, 16 bits (plan 24, decision 1).
RSpec.describe Ruby::Nes::Frontends::Wav do
  describe '.encode' do
    context 'when there are no samples' do
      let(:wav) { described_class.encode([], sample_rate: 48_000) }

      it 'is the 44-byte header with an empty data chunk', :aggregate_failures do
        expect(wav.bytesize).to eq(44)
        expect(wav.byteslice(36, 8)).to eq("data#{[0].pack('V')}")
      end
    end

    context 'when there are samples' do
      let(:wav) { described_class.encode([0, 1, -1, 32_767, -32_768], sample_rate: 48_000) }

      it 'starts with a RIFF chunk whose size counts the WAVE ID and the chunks after it' do
        expect(wav.byteslice(0, 12)).to eq("RIFF#{[4 + 24 + 8 + 10].pack('V')}WAVE")
      end

      it 'describes mono 16-bit PCM at the sample rate in its fmt chunk' do
        expect(wav.byteslice(12, 24)).to eq("fmt #{[16, 1, 1, 48_000, 96_000, 2, 16].pack('VvvVVvv')}")
      end

      it "ends with a data chunk of the samples as little-endian two's complement" do
        expect(wav.byteslice(36..)).to eq("data#{[10].pack('V')}#{"\x00\x00\x01\x00\xFF\xFF\xFF\x7F\x00\x80".b}")
      end
    end
  end
end
