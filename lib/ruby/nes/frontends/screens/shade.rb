# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Screens
        # The paused game's picture dimmed under a menu (plan 38, decision 4): each colour becomes the same hue one value
        # (luma) row lower. A colour index is "VV HHHH", the value in bits 4-5 and the hue in bits 0-3; hues $E-$F are
        # black, $0F is the canonical black, and $0D, "blacker than black", is not to be used
        # (https://www.nesdev.org/wiki/PPU_palettes): the darkest row, the black hues and $1D dim to $0F. A pixel's
        # emphasis bits, 6-8 (docs/architecture.md, Frame buffer contract), are kept. Looked up in a table of the 512
        # pixel values. Off the hot path: once as a menu opens.
        module Shade
          COLOUR_MASK = PpuBus::PaletteRam::COLOUR_MASK
          HUE_MASK = 0x0F
          VALUE_MASK = 0x30
          VALUE_SHIFT = 4
          # One value row of the palette: 16 hues.
          VALUE_ROW = 0x10
          BLACK = 0x0F
          BLACK_HUES = [0x0E, 0x0F].freeze
          BLACKER_THAN_BLACK = 0x0D
          PIXEL_VALUES = 512

          # The colour index one value row below `colour`, or black.
          def self.dimmed_colour(colour)
            return BLACK if BLACK_HUES.include?(Bits.low_bits(colour, HUE_MASK))
            return BLACK if Bits.bit_field(colour, mask: VALUE_MASK, shift: VALUE_SHIFT).zero?

            darker = colour - VALUE_ROW
            darker == BLACKER_THAN_BLACK ? BLACK : darker
          end

          # `pixel` with its colour dimmed, its emphasis bits kept.
          def self.dimmed_pixel(pixel)
            Bits.set_flag(Bits.clear_flag(pixel, COLOUR_MASK), dimmed_colour(Bits.low_bits(pixel, COLOUR_MASK)))
          end

          DIMMED = Array.new(PIXEL_VALUES) { dimmed_pixel(it) }.freeze

          private_class_method :dimmed_colour, :dimmed_pixel

          # A new frame buffer of `frame_buffer`'s pixels dimmed.
          def self.dim(frame_buffer) = frame_buffer.map { DIMMED.fetch(it) }
        end
      end
    end
  end
end
