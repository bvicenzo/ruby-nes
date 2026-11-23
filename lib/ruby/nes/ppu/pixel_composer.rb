# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Draws the renderer's pixels into the picture's drawn frame, through the picture's colour of each palette entry
      # (plan 30, decisions 1 and 6): it holds both, and takes the new drawn frame when the picture completes one. A
      # background entry is 4 bits, 0 when transparent (https://www.nesdev.org/wiki/PPU_palettes); a sprite line entry
      # carries SpriteLine's flags, 0 where no sprite covers the column. Where only one layer is opaque its entry is
      # drawn, a sprite's without its priority and sprite 0 marks; only where both are does the priority multiplexer
      # decide (https://www.nesdev.org/wiki/PPU_sprite_priority). A whole tile is the renderer's 8 background entries
      # in 32 bits, pixel i in bits 31 − 4i to 28 − 4i: the unrolled methods shift by those positions, 28 down to 0,
      # written as literals (docs/architecture.md, Readability, exception 3). Hot path: one call per pixel drawn dot by
      # dot, one per whole tile.
      class PixelComposer
        WIDTH = Picture::WIDTH
        TRANSPARENT = 0
        SPRITE_PALETTE_ENTRY_MASK = SpriteLine::PALETTE_ENTRY_MASK
        PIXEL_MASK = 0x0F

        def initialize(picture:, sprite_entries:, multiplexer:)
          @picture = picture
          @drawn_frame = picture.drawn_frame
          @colours = picture.colours
          @sprite_entries = sprite_entries
          @multiplexer = multiplexer
        end

        # One pixel at column x of row y: the background's entry and the sprite line's, each already 0 where its
        # layer is hidden.
        def draw_pixel(background, sprite, x_position, y_position)
          entry =
            if sprite == TRANSPARENT then background
            elsif background == TRANSPARENT then sprite & SPRITE_PALETTE_ENTRY_MASK # glossary: low-bits
            else @multiplexer.palette_entry(x_position, background, sprite)
            end
          @drawn_frame[(y_position * WIDTH) + x_position] = @colours[entry]
        end

        # A whole tile whose sprites may show, from column x, at `index` in the frame (row × 256 + x): each pixel composed
        # as `draw_pixel` composes it, with the sprite line's entry at its column. Unrolled: a call per pixel costs about
        # a quarter of a visible line. The index comes computed: a local holding it, computed here, made the method
        # about a third slower under YJIT (plan 30, findings).
        # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def draw_tile(pixels, x_position, index)
          entries = @sprite_entries
          frame = @drawn_frame
          colours = @colours
          background = (pixels >> 28) & PIXEL_MASK # glossary: bit-field
          sprite = entries[x_position]
          frame[index] =
            if sprite == TRANSPARENT then colours[background]
            elsif background == TRANSPARENT then colours[sprite & SPRITE_PALETTE_ENTRY_MASK] # glossary: low-bits
            else colours[@multiplexer.palette_entry(x_position, background, sprite)]
            end
          background = (pixels >> 24) & PIXEL_MASK # glossary: bit-field
          sprite = entries[x_position + 1]
          frame[index + 1] =
            if sprite == TRANSPARENT then colours[background]
            elsif background == TRANSPARENT then colours[sprite & SPRITE_PALETTE_ENTRY_MASK] # glossary: low-bits
            else colours[@multiplexer.palette_entry(x_position + 1, background, sprite)]
            end
          background = (pixels >> 20) & PIXEL_MASK # glossary: bit-field
          sprite = entries[x_position + 2]
          frame[index + 2] =
            if sprite == TRANSPARENT then colours[background]
            elsif background == TRANSPARENT then colours[sprite & SPRITE_PALETTE_ENTRY_MASK] # glossary: low-bits
            else colours[@multiplexer.palette_entry(x_position + 2, background, sprite)]
            end
          background = (pixels >> 16) & PIXEL_MASK # glossary: bit-field
          sprite = entries[x_position + 3]
          frame[index + 3] =
            if sprite == TRANSPARENT then colours[background]
            elsif background == TRANSPARENT then colours[sprite & SPRITE_PALETTE_ENTRY_MASK] # glossary: low-bits
            else colours[@multiplexer.palette_entry(x_position + 3, background, sprite)]
            end
          background = (pixels >> 12) & PIXEL_MASK # glossary: bit-field
          sprite = entries[x_position + 4]
          frame[index + 4] =
            if sprite == TRANSPARENT then colours[background]
            elsif background == TRANSPARENT then colours[sprite & SPRITE_PALETTE_ENTRY_MASK] # glossary: low-bits
            else colours[@multiplexer.palette_entry(x_position + 4, background, sprite)]
            end
          background = (pixels >> 8) & PIXEL_MASK # glossary: bit-field
          sprite = entries[x_position + 5]
          frame[index + 5] =
            if sprite == TRANSPARENT then colours[background]
            elsif background == TRANSPARENT then colours[sprite & SPRITE_PALETTE_ENTRY_MASK] # glossary: low-bits
            else colours[@multiplexer.palette_entry(x_position + 5, background, sprite)]
            end
          background = (pixels >> 4) & PIXEL_MASK # glossary: bit-field
          sprite = entries[x_position + 6]
          frame[index + 6] =
            if sprite == TRANSPARENT then colours[background]
            elsif background == TRANSPARENT then colours[sprite & SPRITE_PALETTE_ENTRY_MASK] # glossary: low-bits
            else colours[@multiplexer.palette_entry(x_position + 6, background, sprite)]
            end
          background = pixels & PIXEL_MASK # glossary: low-bits
          sprite = entries[x_position + 7]
          frame[index + 7] =
            if sprite == TRANSPARENT then colours[background]
            elsif background == TRANSPARENT then colours[sprite & SPRITE_PALETTE_ENTRY_MASK] # glossary: low-bits
            else colours[@multiplexer.palette_entry(x_position + 7, background, sprite)]
            end
        end

        # A whole tile whose sprites are hidden, at `index` in the frame: its background entries as they are.
        # rubocop:disable-next Metrics/AbcSize
        def draw_background_tile(pixels, index)
          frame = @drawn_frame
          colours = @colours
          frame[index] = colours[(pixels >> 28) & PIXEL_MASK] # glossary: bit-field
          frame[index + 1] = colours[(pixels >> 24) & PIXEL_MASK] # glossary: bit-field
          frame[index + 2] = colours[(pixels >> 20) & PIXEL_MASK] # glossary: bit-field
          frame[index + 3] = colours[(pixels >> 16) & PIXEL_MASK] # glossary: bit-field
          frame[index + 4] = colours[(pixels >> 12) & PIXEL_MASK] # glossary: bit-field
          frame[index + 5] = colours[(pixels >> 8) & PIXEL_MASK] # glossary: bit-field
          frame[index + 6] = colours[(pixels >> 4) & PIXEL_MASK] # glossary: bit-field
          frame[index + 7] = colours[pixels & PIXEL_MASK] # glossary: low-bits
        end

        # The frame drawn becomes the picture's frame buffer (plan 16, decision 1); the next is drawn into its other
        # buffer.
        def complete_picture
          @picture.complete_frame
          @drawn_frame = @picture.drawn_frame
        end
      end
    end
  end
end
