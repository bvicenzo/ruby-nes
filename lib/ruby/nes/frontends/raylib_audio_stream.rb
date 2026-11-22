# frozen_string_literal: true

require_relative '../audio'

module Ruby
  module Nes
    module Frontends
      # A raylib audio stream (https://www.raylib.com/cheatsheet/cheatsheet.html) as Frontends::AudioPacing sees it
      # (plan 24): two sub-buffers of `chunk_size` signed 16-bit mono samples, set with SetAudioStreamBufferSizeDefault
      # before the stream is loaded. A chunk can be submitted only while a sub-buffer has been played
      # (IsAudioStreamProcessed); one that runs dry plays silence (raudio.c zero-fills it). Opens raylib's audio device,
      # so Frontends::Raylib builds it after loading the library.
      class RaylibAudioStream
        def initialize(sample_rate:, chunk_size:)
          ::Raylib.SetAudioStreamBufferSizeDefault(chunk_size)
          ::Raylib.InitAudioDevice
          @stream = ::Raylib.LoadAudioStream(sample_rate, Audio::BITS_PER_SAMPLE, Audio::CHANNELS)
          @buffer = FFI::MemoryPointer.new(:int16, chunk_size)
          ::Raylib.PlayAudioStream(@stream)
        end

        # Whether the audio device opened and the stream got its buffers: with no usable output device neither does,
        # and the stream would never have room.
        def ready? = ::Raylib.IsAudioDeviceReady && ::Raylib.IsAudioStreamValid(@stream)

        # Whether a sub-buffer has been played and can take a chunk.
        def room? = ::Raylib.IsAudioStreamProcessed(@stream)

        def submit(chunk)
          @buffer.put_array_of_int16(0, chunk)
          ::Raylib.UpdateAudioStream(@stream, @buffer, chunk.size)
        end

        def close
          ::Raylib.UnloadAudioStream(@stream)
          ::Raylib.CloseAudioDevice
        end
      end
    end
  end
end
