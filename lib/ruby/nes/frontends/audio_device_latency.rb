# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The latency the audio device is asked for, set in the environment before raylib opens it (plan 39). A raylib
      # audio stream holds two sub-buffers (Frontends::RaylibAudioStream), each a frame of 800 samples, 16.7 ms at
      # 48 kHz; a device asking for more at a time than fits beside one of them is served silence (raylib zero-fills
      # the rest), and the window paced by its audio slows down: through the Pulse client, which asks for about 1024
      # samples by default, it ran at 53.4 fps. On Linux the Pulse client library, which raylib's audio (miniaudio)
      # loads, reads PULSE_LATENCY_MSEC; a value the user set is kept. Other systems are left alone. Kept apart from
      # the stream so it needs no gem to load.
      module AudioDeviceLatency
        VARIABLE = 'PULSE_LATENCY_MSEC'
        # 5 to 20 measured at 60 fps on PipeWire's Pulse server, 25 already at 53.5 (plan 39). Right only for sub-buffers
        # of 800 samples at 48 kHz (Frontends::Raylib::SAMPLES_PER_FRAME, Audio::SAMPLE_RATE): shorter ones need less.
        LATENCY_MILLISECONDS = '15'
        LINUX = /linux/

        # `environment` is ENV, or a Hash in its place; `host_os` names the system as RbConfig does.
        def self.apply(environment:, host_os:)
          return unless host_os.match?(LINUX)

          environment[VARIABLE] = LATENCY_MILLISECONDS unless environment.has_key?(VARIABLE)
        end
      end
    end
  end
end
