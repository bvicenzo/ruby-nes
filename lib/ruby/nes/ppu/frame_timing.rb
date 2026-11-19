# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Where the PPU is in the NTSC frame (https://www.nesdev.org/wiki/PPU_frame_timing,
      # https://www.nesdev.org/wiki/PPU_rendering): 262 scanlines of 341 dots, advanced one dot at a time. Counts the
      # frames and their even/odd parity, which "is toggled every frame, regardless of whether rendering is enabled".
      # With rendering enabled, odd frames jump "directly from (339,261) ... to (0,0)"; rendering is sampled at dot
      # 339 of the pre-render scanline, so "Turning rendering on late causes the dot at the end of pre-render to never
      # be skipped" (the 3-4 dot delay of a PPUMASK write is a Known gap). Tells `events` when VBlank starts (dot 1 of
      # scanline 241) and ends (dot 1 of the pre-render scanline). "The PPU comes out of power and reset at the top of
      # the picture" (https://www.nesdev.org/wiki/PPU_power_up_state); specs may give the position as keywords.
      #
      # It also owns the PPUSTATUS read race, since it knows the position (plan 12, decision 5): a read "on the dot
      # before it is set (scanline 241, dot 0)" means "the flag is not set and the NMI is not generated for that frame"
      # (https://www.nesdev.org/wiki/PPU_frame_timing), so the next dot does not tell `events` that VBlank started.
      class FrameTiming
        LAST_DOT = 340
        # The dot the odd frame skips from when rendering is enabled: the next one is (0, 0).
        SKIPPED_DOT = 339
        VERTICAL_BLANK_SCANLINE = 241
        PRE_RENDER_SCANLINE = 261
        # The VBlank flag changes at this dot of its scanlines.
        VERTICAL_BLANK_DOT = 1

        attr_reader :scanline, :dot, :frame_number
        # Whether PPUMASK shows the background or the sprites (bits 3-4), told by the Ppu.
        attr_writer :rendering_enabled

        # One optional keyword per piece of the frame's state, so specs can start anywhere in a frame.
        # rubocop:disable-next Metrics/ParameterLists
        def initialize(events:, scanline: 0, dot: 0, odd_frame: false, rendering_enabled: false, frame_number: 0)
          @events = events
          @scanline = scanline
          @dot = dot
          @odd_frame = odd_frame
          @rendering_enabled = rendering_enabled
          @frame_number = frame_number
          @vertical_blank_cancelled = false
        end

        def odd_frame? = @odd_frame

        # Moves to the next dot, wrapping to the next scanline and to the next frame.
        def advance
          if @dot == LAST_DOT
            next_scanline
          elsif @dot == SKIPPED_DOT && @scanline == PRE_RENDER_SCANLINE && @odd_frame && @rendering_enabled
            next_frame
          else
            @dot += 1
            tell_vertical_blank if @dot == VERTICAL_BLANK_DOT
          end
        end

        # The Ppu read PPUSTATUS on the current dot.
        def status_read
          @vertical_blank_cancelled = true if @scanline == VERTICAL_BLANK_SCANLINE && @dot.zero?
        end

        # Back to the top of the picture, on an even frame; the frame count goes on, and a pending read race no longer
        # applies.
        def reset
          @scanline = 0
          @dot = 0
          @odd_frame = false
          @vertical_blank_cancelled = false
        end

        private

        def next_scanline
          if @scanline == PRE_RENDER_SCANLINE
            next_frame
          else
            @scanline += 1
            @dot = 0
          end
        end

        def next_frame
          @scanline = 0
          @dot = 0
          @frame_number += 1
          @odd_frame = !@odd_frame
        end

        def tell_vertical_blank
          if @scanline == VERTICAL_BLANK_SCANLINE
            start_vertical_blank
          elsif @scanline == PRE_RENDER_SCANLINE
            @events.vertical_blank_ended
          end
        end

        def start_vertical_blank
          if @vertical_blank_cancelled
            @vertical_blank_cancelled = false
          else
            @events.vertical_blank_started
          end
        end
      end
    end
  end
end
