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
        # Rendering's updates of v ("Wrapping around"): bit 10 switches the horizontal nametable, bit 11 the vertical
        # one; "hori(v)" is ".....A.. ...BCDEF" and "vert(v)" "GHIA.BC DEF.....".
        HORIZONTAL_NAMETABLE_FLAG = 0x0400
        VERTICAL_NAMETABLE_FLAG = 0x0800
        HORIZONTAL_POSITION_MASK = HORIZONTAL_NAMETABLE_FLAG | COARSE_X_MASK
        VERTICAL_POSITION_MASK = FINE_Y_MASK | VERTICAL_NAMETABLE_FLAG | COARSE_Y_MASK
        # One step of fine Y and of coarse Y, in place.
        FINE_Y_STEP = 1 << FINE_Y_SHIFT
        COARSE_Y_STEP = 1 << COARSE_Y_SHIFT
        # Coarse Y 29, in place: the last of the 30 tile rows, after which the vertical nametable switches. Software
        # can set 30 and 31, which wrap to 0 "nametable not switched".
        LAST_TILE_ROW = 29 << COARSE_Y_SHIFT

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

        # The PPU's reset signal clears PPUSCROLL, PPUADDR and their latch: t, fine x and w; "the VRAM address itself
        # (V) is _not_ cleared" (https://www.nesdev.org/wiki/PPU_power_up_state).
        def reset
          @temporary_address = 0
          @fine_x = 0
          @second_write = false
        end

        # A PPUDATA access outside rendering adds "either 1 or 32 to v"; v keeps its 15 bits.
        def increment_vram_address(increment)
          @vram_address = (@vram_address + increment) & VRAM_ADDRESS_MASK # glossary: low-bits
        end

        # Rendering, every 8 dots: "if coarse X == 31", coarse X = 0 and "switch horizontal nametable", else coarse X +
        # 1.
        def increment_coarse_x
          if @vram_address.allbits?(COARSE_X_MASK)
            @vram_address &= ~COARSE_X_MASK # glossary: clear-flag
            @vram_address ^= HORIZONTAL_NAMETABLE_FLAG # glossary: toggle-flag
          else
            @vram_address += 1
          end
        end

        # Rendering, dot 256: "if fine Y < 7", fine Y + 1; else fine Y = 0 and coarse Y moves to the next row.
        def increment_y
          if @vram_address.allbits?(FINE_Y_MASK)
            @vram_address &= ~FINE_Y_MASK # glossary: clear-flag
            increment_coarse_y
          else
            @vram_address += FINE_Y_STEP
          end
        end

        # Rendering, dot 257: "v: ....A.. ...BCDEF <- t: ....A.. ...BCDEF".
        def copy_horizontal_position
          horizontal_position = @temporary_address & HORIZONTAL_POSITION_MASK # glossary: bitwise-and
          @vram_address = (@vram_address & ~HORIZONTAL_POSITION_MASK) | horizontal_position # glossary: place-bit-field
        end

        # Rendering, dots 280-304 of the pre-render scanline: "v: GHIA.BC DEF..... <- t: GHIA.BC DEF.....".
        def copy_vertical_position
          vertical_position = @temporary_address & VERTICAL_POSITION_MASK # glossary: bitwise-and
          @vram_address = (@vram_address & ~VERTICAL_POSITION_MASK) | vertical_position # glossary: place-bit-field
        end

        private

        # "if (y == 29)" coarse Y = 0 and "switch vertical nametable"; "else if (y == 31)" coarse Y = 0, "nametable not
        # switched"; else coarse Y + 1.
        def increment_coarse_y
          coarse_y = @vram_address & COARSE_Y_MASK # glossary: bitwise-and
          if coarse_y == LAST_TILE_ROW
            @vram_address &= ~COARSE_Y_MASK # glossary: clear-flag
            @vram_address ^= VERTICAL_NAMETABLE_FLAG # glossary: toggle-flag
          elsif coarse_y == COARSE_Y_MASK
            @vram_address &= ~COARSE_Y_MASK # glossary: clear-flag
          else
            @vram_address += COARSE_Y_STEP
          end
        end
      end
    end
  end
end
