# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Screens
        # The menus' pixel font (plan 37, decision 4), drawn for this project: upper case letters, digits,
        # punctuation and the marks' icons, each a glyph of 5 × 7 pixels in a cell of 8 × 8, from its second column and
        # its first row, so characters side by side and lines one under the other keep a gap. A glyph only colours its
        # own pixels; the rest of the cell keeps what is under it. Text from outside ruby-nes (a file name) is made
        # printable first. Off the hot path: once per menu frame.
        module PixelFont
          CELL_SIZE = 8
          GLYPH_LEFT = 1
          SET = '#'
          # The marks Unicode decomposes accented letters into (canonical decomposition, NFD).
          COMBINING_MARKS = /\p{Mn}/
          NOT_DRAWABLE = '?'
          # A battery-backed save, a save state, the cursor, and more of the list above and below.
          BATTERY_SAVE_MARK = '♥'
          SAVE_STATE_MARK = '★'
          CURSOR = '▶'
          MORE_ABOVE = '▲'
          MORE_BELOW = '▼'
          # Each character's rows, top to bottom, `#` for a pixel of the glyph.
          GLYPH_ROWS = {
            ' ' => %w[..... ..... ..... ..... ..... ..... .....],
            'A' => %w[.###. #...# #...# ##### #...# #...# #...#],
            'B' => %w[####. #...# #...# ####. #...# #...# ####.],
            'C' => %w[.###. #...# #.... #.... #.... #...# .###.],
            'D' => %w[####. #...# #...# #...# #...# #...# ####.],
            'E' => %w[##### #.... #.... ####. #.... #.... #####],
            'F' => %w[##### #.... #.... ####. #.... #.... #....],
            'G' => %w[.###. #...# #.... #.### #...# #...# .####],
            'H' => %w[#...# #...# #...# ##### #...# #...# #...#],
            'I' => %w[.###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.],
            'J' => %w[..### ...#. ...#. ...#. ...#. #..#. .##..],
            'K' => %w[#...# #..#. #.#.. ##... #.#.. #..#. #...#],
            'L' => %w[#.... #.... #.... #.... #.... #.... #####],
            'M' => %w[#...# ##.## #.#.# #.#.# #...# #...# #...#],
            'N' => %w[#...# #...# ##..# #.#.# #..## #...# #...#],
            'O' => %w[.###. #...# #...# #...# #...# #...# .###.],
            'P' => %w[####. #...# #...# ####. #.... #.... #....],
            'Q' => %w[.###. #...# #...# #...# #.#.# #..#. .##.#],
            'R' => %w[####. #...# #...# ####. #.#.. #..#. #...#],
            'S' => %w[.#### #.... #.... .###. ....# ....# ####.],
            'T' => %w[##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..],
            'U' => %w[#...# #...# #...# #...# #...# #...# .###.],
            'V' => %w[#...# #...# #...# #...# #...# .#.#. ..#..],
            'W' => %w[#...# #...# #...# #.#.# #.#.# #.#.# .#.#.],
            'X' => %w[#...# #...# .#.#. ..#.. .#.#. #...# #...#],
            'Y' => %w[#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..],
            'Z' => %w[##### ....# ...#. ..#.. .#... #.... #####],
            '0' => %w[.###. #...# #..## #.#.# ##..# #...# .###.],
            '1' => %w[..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.],
            '2' => %w[.###. #...# ....# ...#. ..#.. .#... #####],
            '3' => %w[##### ...#. ..#.. ...#. ....# #...# .###.],
            '4' => %w[...#. ..##. .#.#. #..#. ##### ...#. ...#.],
            '5' => %w[##### #.... ####. ....# ....# #...# .###.],
            '6' => %w[..##. .#... #.... ####. #...# #...# .###.],
            '7' => %w[##### ....# ...#. ..#.. .#... .#... .#...],
            '8' => %w[.###. #...# #...# .###. #...# #...# .###.],
            '9' => %w[.###. #...# #...# .#### ....# ...#. .##..],
            '.' => %w[..... ..... ..... ..... ..... .##.. .##..],
            ',' => %w[..... ..... ..... ..... .##.. ..#.. .#...],
            ';' => %w[..... .##.. .##.. ..... .##.. ..#.. .#...],
            ':' => %w[..... .##.. .##.. ..... .##.. .##.. .....],
            "'" => %w[..#.. ..#.. .#... ..... ..... ..... .....],
            '"' => %w[.#.#. .#.#. ..... ..... ..... ..... .....],
            '-' => %w[..... ..... ..... ##### ..... ..... .....],
            '_' => %w[..... ..... ..... ..... ..... ..... #####],
            '+' => %w[..... ..#.. ..#.. ##### ..#.. ..#.. .....],
            '=' => %w[..... ..... ##### ..... ##### ..... .....],
            '*' => %w[..... #.#.# .###. ##### .###. #.#.# .....],
            '!' => %w[..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..],
            '?' => %w[.###. #...# ....# ...#. ..#.. ..... ..#..],
            '&' => %w[.##.. #..#. #.#.. .#... #.#.# #..#. .##.#],
            '#' => %w[.#.#. .#.#. ##### .#.#. ##### .#.#. .#.#.],
            '%' => %w[##... ##..# ...#. ..#.. .#... #..## ...##],
            '/' => %w[..... ....# ...#. ..#.. .#... #.... .....],
            '(' => %w[...#. ..#.. .#... .#... .#... ..#.. ...#.],
            ')' => %w[.#... ..#.. ...#. ...#. ...#. ..#.. .#...],
            '[' => %w[.###. .#... .#... .#... .#... .#... .###.],
            ']' => %w[.###. ...#. ...#. ...#. ...#. ...#. .###.],
            BATTERY_SAVE_MARK => %w[..... .#.#. ##### ##### .###. ..#.. .....],
            SAVE_STATE_MARK => %w[..#.. ..#.. ##### .###. .#.#. #...# .....],
            CURSOR => %w[.#... .##.. .###. .#### .###. .##.. .#...],
            MORE_ABOVE => %w[..... ..#.. .###. ##### ..... ..... .....],
            MORE_BELOW => %w[..... ..... ..... ##### .###. ..#.. .....]
          }.freeze
          # Each glyph as the offsets of its pixels from its cell's top left corner, `[column, row]`.
          GLYPHS = GLYPH_ROWS.transform_values do |rows|
            offsets = rows.each_with_index.flat_map do |pixels, row|
              pixels.size.times.select { pixels[it] == SET }.map { [GLYPH_LEFT + it, row].freeze }
            end
            offsets.freeze
          end
          GLYPHS.freeze

          # Draws `text` into `frame_buffer` (256 × 240 palette indices, docs/architecture.md, Frame buffer contract)
          # with the top left corner of its first cell at column `left`, row `top`, in the palette index `colour`;
          # raises ArgumentError, drawing nothing, when a character has no glyph. The caller keeps the text inside the
          # frame.
          def self.draw(text, frame_buffer, left:, top:, colour:)
            missing = text.each_char.reject { drawable?(it) }
            raise ArgumentError, "no glyph for #{missing.uniq.map(&:inspect).join(', ')}" if missing.any?

            text.each_char.with_index do |character, index|
              cell_left = left + (index * CELL_SIZE)
              GLYPHS.fetch(character).each do |column, row|
                frame_buffer[((top + row) * Ppu::Picture::WIDTH) + cell_left + column] = colour
              end
            end
          end

          # `text` in upper case, its accents dropped and "?" for any other character without a glyph.
          def self.printable(text)
            text
              .unicode_normalize(:nfd)
              .gsub(COMBINING_MARKS, '')
              .upcase
              .each_char
              .map { drawable?(it) ? it : NOT_DRAWABLE }
              .join
          end

          def self.drawable?(character) = GLYPHS.has_key?(character)
        end
      end
    end
  end
end
