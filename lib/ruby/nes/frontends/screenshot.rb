# frozen_string_literal: true

require_relative 'palette'
require_relative 'png'

module Ruby
  module Nes
    module Frontends
      # A frame as a PNG image: the headless frontend's screenshots (plan 16) and the save states' pictures (plan 35,
      # decision 7). Off the hot path: about 2 ms a frame.
      module Screenshot
        # The PNG image of a frame buffer (docs/architecture.md, Frame buffer contract), in Frontends::Palette's
        # colours.
        def self.png(frame_buffer)
          Png.encode(width: Ppu::Picture::WIDTH, height: Ppu::Picture::HEIGHT, rgb: Palette.rgb(frame_buffer))
        end
      end
    end
  end
end
