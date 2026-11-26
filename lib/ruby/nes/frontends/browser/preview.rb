# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Browser
        # The preview of the game in focus (plan 37, decision 2): a console of its own, silent and without its battery
        # save, built when the game takes the focus. Its cached preview state (Browser::PreviewCache, by the ROM's
        # SHA-256) is restored at once, its frame buffer being the still picture. Once the cursor has rested REST_FRAMES
        # frames (ticks), the console runs a frame on each tick after: from the cached state, or else from power-up,
        # watched (Browser::MotionWatch) until its picture moves or `frame_limit` frames have run, when its state is
        # cached, once. A cached state ruby-nes refuses (Saves::InvalidState) is as none, and is made again. A ROM that
        # cannot be run or loaded has no console and no picture; one whose cartridge cannot be loaded has a `problem`,
        # since Browser::RomList reads only the header. Off the hot path: once per menu frame; building a
        # console takes 1-3 ms and restoring a state about 4 ms, within a frame.
        class Preview
          # About half a second at 60.0988 frames per second (https://www.nesdev.org/wiki/Cycle_reference_chart).
          REST_FRAMES = 30
          # About a minute: a game whose picture has not moved by then is cached as it is.
          FRAME_LIMIT = 3600

          # `cache` is a Browser::PreviewCache; `load_cartridge` reads the cartridge at a path and `new_motion_watch`
          # gives a Browser::MotionWatch, both for the specs.
          def initialize(
            cache:,
            load_cartridge: Cartridge::Loader.method(:from_file),
            new_motion_watch: MotionWatch.method(:new),
            frame_limit: FRAME_LIMIT
          )
            @cache = cache
            @load_cartridge = load_cartridge
            @new_motion_watch = new_motion_watch
            @frame_limit = frame_limit
            @console = nil
            @shown = false
            @problem = nil
          end

          # Why the cartridge of the game in focus cannot be loaded, printable (Browser::PixelFont), or nil.
          attr_reader :problem

          # Takes `rom` (a Browser::Rom) as the game in focus, in place of the one before.
          def focus(rom)
            @console = nil
            @problem = nil
            @shown = false
            @frames_rested = 0
            @motion_watch = nil
            @frames_watched = 0
            return unless rom.playable?

            @console = Console.new(@load_cartridge.call(rom.path))
            @state = Saves::ConsoleState.new(@console)
            @learning = !restore_cached
          rescue Nes::Error, SystemCallError => error
            @console = nil
            @problem = PixelFont.printable(error.message)
          end

          # Counts a menu frame the cursor rested on the game, and runs the game's next frame once it has rested.
          def tick
            return unless @console

            @frames_rested += 1
            return if @frames_rested <= REST_FRAMES

            @console.run_frame
            @shown = true
            learn if @learning
          end

          # The picture to show (docs/architecture.md, Frame buffer contract), or nil while there is none.
          def frame_buffer = (@console.ppu.frame_buffer if @shown)

          private

          # Whether the cached state was restored.
          def restore_cached
            bytes = @cache.read(@state.rom_digest)
            return false unless bytes

            @state.restore(bytes)
            @shown = true
          rescue Saves::InvalidState
            false
          end

          def learn
            @motion_watch ||= @new_motion_watch.call
            @frames_watched += 1
            @motion_watch.watch(@console.ppu.frame_buffer)
            return unless @motion_watch.moving? || @frames_watched >= @frame_limit

            @cache.write(@state.rom_digest, @state.encode)
            @learning = false
          end
        end
      end
    end
  end
end
