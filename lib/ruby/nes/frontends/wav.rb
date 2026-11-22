# frozen_string_literal: true

require_relative '../audio'

module Ruby
  module Nes
    module Frontends
      # A minimal WAVE encoder (https://www.mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/WAVE.html) for the headless
      # frontend's audio (plan 24): mono, signed 16-bit PCM (Audio::BITS_PER_SAMPLE, Audio::CHANNELS). The file is "a
      # master RIFF chunk which includes a WAVE identifier followed by sub-chunks", the fmt chunk and the data chunk,
      # "stored in little-endian byte order"; PCM samples of more than 8 bits are two's complement. Off the hot path.
      module Wav
        # The fmt chunk of PCM: format code, channels, sample rate, data rate, block size, bits per sample (16 bytes).
        PCM = 1
        BYTES_PER_SAMPLE = Audio::BITS_PER_SAMPLE / 8

        # The WAVE file of signed 16-bit samples at `sample_rate` samples per second. The RIFF chunk holds the WAVE ID
        # and the other chunks, so its size is "4+n".
        def self.encode(samples, sample_rate:)
          chunk('RIFF', 'WAVE'.b + chunk('fmt ', format(sample_rate)) + chunk('data', samples.pack('s<*')))
        end

        # A chunk: its ID, the size of its contents, little-endian, and its contents.
        def self.chunk(id, contents)
          id.b + [contents.bytesize].pack('V') + contents
        end

        def self.format(sample_rate)
          block_size = Audio::CHANNELS * BYTES_PER_SAMPLE
          fields = [PCM, Audio::CHANNELS, sample_rate, sample_rate * block_size, block_size, Audio::BITS_PER_SAMPLE]
          fields.pack('vvVVvv')
        end

        private_class_method :chunk, :format
      end
    end
  end
end
