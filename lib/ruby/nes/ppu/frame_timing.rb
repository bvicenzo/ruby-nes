# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Where the PPU is in the NTSC frame (https://www.nesdev.org/wiki/PPU_frame_timing,
      # https://www.nesdev.org/wiki/PPU_rendering): 262 scanlines of 341 dots, advanced one dot at a time, or within a
      # scanline to a later dot that tells nothing (plan 28, decision 4). Counts the frames and their even/odd parity,
      # which "is toggled every frame, regardless of whether rendering is enabled". With rendering enabled, odd frames
      # jump "directly from (339,261) ... to (0,0)"; rendering is sampled at dot 339 of the pre-render scanline, so
      # "Turning rendering on late causes the dot at the end of pre-render to never be skipped" (the 3-4 dot delay of a
      # PPUMASK write is a Known gap). Tells `events` when VBlank starts (dot 1 of scanline 241) and ends (dot 1 of the
      # pre-render scanline), and when the picture is complete: on entering the post-render scanline, after the last
      # visible pixel (plan 16, decision 1). "The PPU comes out of power and reset at the top of the picture"
      # (https://www.nesdev.org/wiki/PPU_power_up_state); specs may give the position as keywords.
      #
      # It also owns the PPUSTATUS read race, since it knows the position (plan 12, decision 5): a read "on the dot
      # before it is set (scanline 241, dot 0)" means "the flag is not set and the NMI is not generated for that frame"
      # (https://www.nesdev.org/wiki/PPU_frame_timing), so the next dot does not tell `events` that VBlank started.
      class FrameTiming
        LAST_DOT = 340
        # The dot the odd frame skips from when rendering is enabled: the next one is (0, 0).
        SKIPPED_DOT = 339
        # Scanlines 0-239 are visible; 240 is the post-render one.
        POST_RENDER_SCANLINE = 240
        VERTICAL_BLANK_SCANLINE = 241
        PRE_RENDER_SCANLINE = 261
        # The VBlank flag changes at this dot of its scanlines.
        VERTICAL_BLANK_DOT = 1
        DOTS_PER_SCANLINE = LAST_DOT + 1
        # Positions within the frame, counted in dots from (0, 0): where VBlank starts and ends, and the next frame's
        # first dot when none is skipped.
        VERTICAL_BLANK_START = (VERTICAL_BLANK_SCANLINE * DOTS_PER_SCANLINE) + VERTICAL_BLANK_DOT
        VERTICAL_BLANK_END = (PRE_RENDER_SCANLINE * DOTS_PER_SCANLINE) + VERTICAL_BLANK_DOT
        FRAME_DOTS = (PRE_RENDER_SCANLINE + 1) * DOTS_PER_SCANLINE

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

        # "During rendering (on the pre-render line and the visible lines 0-239, provided either background or sprite
        # rendering is enabled)" (https://www.nesdev.org/wiki/PPU_scrolling).
        def rendering_in_progress?
          @rendering_enabled && (@scanline < POST_RENDER_SCANLINE || @scanline == PRE_RENDER_SCANLINE)
        end

        # Moves to the next dot, wrapping to the next scanline and to the next frame.
        def advance
          if @dot == LAST_DOT
            next_scanline
          elsif @dot == SKIPPED_DOT && skipping_dot?
            next_frame
          else
            @dot += 1
            tell_vertical_blank if @dot == VERTICAL_BLANK_DOT
          end
        end

        # The dots up to the next one whose entry tells `events` that VBlank starts or ends, or starts the next frame
        # (plan 28, decision 2); the picture's completion reaches only the renderer. Counts the odd frame's skipped dot
        # as rendering stands now: a PPUMASK write that changes it catches the PPU up first.
        def dots_to_next_event
          position = (@scanline * DOTS_PER_SCANLINE) + @dot
          if position < VERTICAL_BLANK_START then VERTICAL_BLANK_START - position
          elsif position < VERTICAL_BLANK_END then VERTICAL_BLANK_END - position
          else FRAME_DOTS - position - (skipping_dot? ? 1 : 0)
          end
        end

        # The last dot of the scanline a range can reach from the current one without telling an event or leaving the
        # scanline (plan 28, decision 4): dot 0 itself on the scanlines whose dot 1 changes VBlank, the skipped dot on
        # an odd frame's pre-render scanline with rendering enabled, the last dot otherwise.
        def last_quiet_dot
          if @dot.zero? then vertical_blank_edge_scanline? ? @dot : LAST_DOT
          elsif skipping_dot? then SKIPPED_DOT
          else LAST_DOT
          end
        end

        # A range ran the scanline's dots up to `dot`, a quiet one (`last_quiet_dot`): nothing is told.
        def advance_to(dot)
          @dot = dot
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

        # The scanlines whose dot 1 starts or ends VBlank.
        def vertical_blank_edge_scanline? = @scanline == VERTICAL_BLANK_SCANLINE || @scanline == PRE_RENDER_SCANLINE

        # On the pre-render scanline of an odd frame with rendering enabled, before the dot it jumps from.
        def skipping_dot?
          @scanline == PRE_RENDER_SCANLINE && @odd_frame && @rendering_enabled && @dot <= SKIPPED_DOT
        end

        def next_scanline
          if @scanline == PRE_RENDER_SCANLINE
            next_frame
          else
            @scanline += 1
            @dot = 0
            @events.picture_completed if @scanline == POST_RENDER_SCANLINE
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
