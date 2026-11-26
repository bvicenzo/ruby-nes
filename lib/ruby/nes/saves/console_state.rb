# frozen_string_literal: true

require 'digest'
require 'zlib'

module Ruby
  module Nes
    module Saves
      # A console's save state as bytes (plan 35, decisions 1 and 2): a header, then the console's snapshot
      # (Console#snapshot, without the ROM) compressed with zlib. The header (HEADER_LAYOUT) holds MAGIC, the format's
      # version, the SHA-256 of the ROM (PRG then CHR), the sample rate the console mixes at (NO_SOUND without; a
      # console with sound holds more objects) and a fingerprint of the code: the SHA-256 of the console's shape
      # (Saves::Shape) and of the core's constants (Saves::ConstantsDigest), whose tables the state carries by value. A
      # state is restored only when all of them match the console's, checked before the snapshot is loaded: Marshal can
      # build any object (https://docs.ruby-lang.org/en/master/Marshal.html), so states are only read from the
      # emulator's own directory. A snapshot Marshal still cannot load (code changed where the fingerprint does not
      # look) is refused too. The ROM's digest and the fingerprint do not change as the console runs, so each is taken
      # once. Off the hot path.
      class ConsoleState
        MAGIC = "ruby-nes state\n".b.freeze
        FORMAT_VERSION = 1
        # A SHA-256 in hexadecimal.
        DIGEST_SIZE = 64
        VERSION_SIZE = 1
        SAMPLE_RATE_SIZE = 4
        # MAGIC, the format's version (a byte), the ROM's digest, the sample rate (32 bits, big-endian), the code's
        # fingerprint.
        HEADER_LAYOUT = "a#{MAGIC.bytesize}Ca#{DIGEST_SIZE}Na#{DIGEST_SIZE}".freeze
        HEADER_SIZE = MAGIC.bytesize + VERSION_SIZE + DIGEST_SIZE + SAMPLE_RATE_SIZE + DIGEST_SIZE
        NO_SOUND = 0
        # The parts of Ruby::Nes that are not the console: a state holds none of them.
        NOT_CORE = %i[Frontends Saves CommandLine Debug].freeze
        UNSIGNED_BYTES = 'C*'

        def initialize(console)
          @console = console
          @rom_digest = nil
          @fingerprint = nil
        end

        def encode
          header = [MAGIC, FORMAT_VERSION, rom_digest, sample_rate, fingerprint].pack(HEADER_LAYOUT)
          header + Zlib::Deflate.deflate(@console.snapshot)
        end

        # Brings the console to the moment of the state in `bytes`; raises InvalidState, leaving the console as it was,
        # when they are not a state of this format, ROM, sound and code, or are damaged.
        def restore(bytes)
          bytes = bytes.b
          check_header(bytes)
          @console.restore(Zlib::Inflate.inflate(bytes.byteslice(HEADER_SIZE..)))
        rescue Zlib::Error
          raise InvalidState, 'damaged'
        rescue ArgumentError, TypeError, NameError
          raise InvalidState, 'cannot be read by this version of ruby-nes'
        end

        # The SHA-256 of the console's ROM, its PRG ROM then its CHR ROM (none with CHR RAM), in hexadecimal: the
        # header's, and the key of the ROM browser's preview cache (plan 37, decision 2).
        def rom_digest
          cartridge = @console.cartridge
          @rom_digest ||= Digest::SHA256.hexdigest((cartridge.prg_rom + cartridge.chr_rom).pack(UNSIGNED_BYTES))
        end

        private

        def check_header(bytes)
          raise InvalidState, 'not a ruby-nes state' unless bytes.start_with?(MAGIC)
          raise InvalidState, 'saved in another format' unless bytes.getbyte(MAGIC.bytesize) == FORMAT_VERSION
          raise InvalidState, 'damaged' if bytes.bytesize < HEADER_SIZE

          _magic, _version, rom_digest, sample_rate, fingerprint = bytes.unpack(HEADER_LAYOUT)
          raise InvalidState, 'saved from another ROM' unless rom_digest == self.rom_digest

          check_sound(sample_rate)
          raise InvalidState, 'saved by another version of ruby-nes' unless fingerprint == self.fingerprint
        end

        def check_sound(sample_rate)
          return if sample_rate == self.sample_rate
          raise InvalidState, 'saved with the sound off (--no-audio)' if sample_rate == NO_SOUND

          raise InvalidState, 'saved with the sound on (without --no-audio)'
        end

        def sample_rate = @console.audio_sample_rate || NO_SOUND

        def fingerprint
          @fingerprint ||= Digest::SHA256.hexdigest(Shape.digest(@console) + ConstantsDigest.of(Nes, except: NOT_CORE))
        end
      end
    end
  end
end
