# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The part of the frame a window shows, and the window's size (plan 18, decision 4): the frame scaled by an
      # integer, its pixels square or stretched to "the pixel aspect ratio on a 4:3 TV", "exactly 8:7", and, with the
      # overscan cropped, only "lines 8 to 231", as "Emulators and LCD HDTVs tend to use"
      # (https://www.nesdev.org/wiki/Overscan). Off the hot path: built once.
      class Viewport
        # A rectangle of the frame, in pixels from its top left corner.
        Rectangle = Data.define(:x, :y, :width, :height)

        OVERSCAN_LINES = 8
        WHOLE_FRAME = Rectangle.new(x: 0, y: 0, width: Ppu::Picture::WIDTH, height: Ppu::Picture::HEIGHT)
        CROPPED_FRAME = Rectangle.new(
          x: 0, y: OVERSCAN_LINES, width: Ppu::Picture::WIDTH, height: Ppu::Picture::HEIGHT - (2 * OVERSCAN_LINES)
        )

        # The part of the frame shown.
        attr_reader :source

        # `pixel_aspect` is a pixel's width over its height (1, or Rational(8, 7)).
        def initialize(scale:, pixel_aspect:, crop_overscan:)
          @scale = scale
          @pixel_aspect = pixel_aspect
          @source = crop_overscan ? CROPPED_FRAME : WHOLE_FRAME
        end

        # The window's width, in screen pixels.
        def width = (@source.width * @scale * @pixel_aspect).round

        # The window's height, in screen pixels.
        def height = @source.height * @scale
      end
    end
  end
end
