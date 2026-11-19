# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The PPU's internal scroll and address registers (https://www.nesdev.org/wiki/PPU_scrolling), named by NESdev
      # after their letters: v, the "Current VRAM address (15 bits)" (`vram_address`); t, the "Temporary VRAM address
      # (15 bits)" (`temporary_address`); x, the fine X scroll (3 bits, `fine_x`); and w, the write toggle "shared by
      # $2005 and $2006" (`second_write?`). Each method is one row of the page's "Register controls" table; t's fields
      # are, from bit 0, coarse X (5 bits), coarse Y (5), nametable select (2) and fine Y (3). Everything starts at
      # zero; specs may declare any state as keywords.
      class ScrollRegisters
        # The fields of t (and v), "yyy NN YYYYY XXXXX".
        COARSE_X_MASK = 0x001F
        COARSE_Y_MASK = 0x03E0
        COARSE_Y_SHIFT = 5
        NAMETABLE_SELECT_MASK = 0x0C00
        NAMETABLE_SELECT_SHIFT = 10
        FINE_Y_MASK = 0x7000
        FINE_Y_SHIFT = 12
        Y_SCROLL_MASK = FINE_Y_MASK | COARSE_Y_MASK
        # The first PPUADDR write replaces t bits 14-8: bits 13-8 from the value, bit 14 cleared ("bit Z is cleared").
        ADDRESS_HIGH_MASK = 0x3F00
        FIRST_WRITE_MASK = 0x7F00
        # A PPUSCROLL value: bits 2-0 are the fine scroll, bits 7-3 the coarse one.
        FINE_SCROLL_MASK = 0x07
        COARSE_SCROLL_SHIFT = 3
        # v and t have 15 bits.
        VRAM_ADDRESS_MASK = 0x7FFF

        attr_reader :vram_address, :temporary_address, :fine_x

        def initialize(vram_address: 0, temporary_address: 0, fine_x: 0, second_write: false)
          @vram_address = vram_address
          @temporary_address = temporary_address
          @fine_x = fine_x
          @second_write = second_write
        end

        # w: whether the next PPUSCROLL or PPUADDR write is the second of its pair.
        def second_write? = @second_write

        # PPUCTRL: "t: ...GH.. ........ <- d: ......GH".
        def write_control(value)
          nametable = (value << NAMETABLE_SELECT_SHIFT) & NAMETABLE_SELECT_MASK # glossary: place-bit-field
          @temporary_address = (@temporary_address & ~NAMETABLE_SELECT_MASK) | nametable # glossary: place-bit-field
        end

        # PPUSCROLL. First write: "t: ....... ...ABCDE <- d: ABCDE...", "x: FGH <- d: .....FGH", "w: <- 1". Second
        # write: "t: FGH..AB CDE..... <- d: ABCDEFGH", "w: <- 0".
        def write_scroll(value)
          if @second_write
            fine_y = (value << FINE_Y_SHIFT) & FINE_Y_MASK # glossary: place-bit-field
            coarse_y = (value >> COARSE_SCROLL_SHIFT) << COARSE_Y_SHIFT # glossary: bit-field, place-bit-field
            @temporary_address = (@temporary_address & ~Y_SCROLL_MASK) | fine_y | coarse_y # glossary: place-bit-field
          else
            coarse_x = value >> COARSE_SCROLL_SHIFT # glossary: bit-field
            @temporary_address = (@temporary_address & ~COARSE_X_MASK) | coarse_x # glossary: place-bit-field
            @fine_x = value & FINE_SCROLL_MASK # glossary: low-bits
          end
          @second_write = !@second_write
        end

        # PPUADDR, "high byte first". First write: "t: .CDEFGH ........ <- d: ..CDEFGH", "t: Z...... ........ <- 0",
        # "w: <- 1". Second write: "t: ....... ABCDEFGH <- d: ABCDEFGH", "v: <...all bits...> <- t: <...all bits...>",
        # "w: <- 0".
        def write_address(value)
          if @second_write
            @temporary_address = (@temporary_address & ~Bits::BYTE_MASK) | value # glossary: place-bit-field
            @vram_address = @temporary_address
          else
            high_bits = (value << 8) & ADDRESS_HIGH_MASK # glossary: place-bit-field
            @temporary_address = (@temporary_address & ~FIRST_WRITE_MASK) | high_bits # glossary: place-bit-field
          end
          @second_write = !@second_write
        end

        # A PPUSTATUS read: "w: <- 0".
        def reset_write_toggle
          @second_write = false
        end

        # A PPUDATA access outside rendering adds "either 1 or 32 to v"; v keeps its 15 bits.
        def increment_vram_address(increment)
          @vram_address = (@vram_address + increment) & VRAM_ADDRESS_MASK # glossary: low-bits
        end
      end
    end
  end
end
