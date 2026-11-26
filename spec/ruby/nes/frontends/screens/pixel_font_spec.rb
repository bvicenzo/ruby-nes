# frozen_string_literal: true

require 'ruby/nes/frontends/screens'

# The menus' 8×8 pixel font (plan 37, decision 4): upper case letters, digits, punctuation and the marks' icons,
# drawn into a frame buffer of 256 × 240 palette indices, one 8-pixel cell per character from the position given, in
# one colour. Only the glyph's own pixels change: what lies under the rest of each cell stays. The text comes from
# ruby-nes's own code, or is made printable first, so a character without a glyph is a bug: it raises, before any pixel
# is drawn. Printable text is upper case, without accents, with "?" for any other character without a glyph.
RSpec.describe Ruby::Nes::Frontends::Screens::PixelFont do
  describe '.draw' do
    context 'when a character has no glyph' do
      let(:frame_buffer) { Array.new(256 * 240, 0x0F) }

      it 'raises ArgumentError naming it, drawing nothing', :aggregate_failures do
        expect { described_class.draw('Ab', frame_buffer, left: 8, top: 8, colour: 0x30) }
          .to raise_error(ArgumentError, /"b"/)
        expect(frame_buffer.uniq).to eq([0x0F])
      end
    end

    context 'when every character has a glyph' do
      let(:frame_buffer) { Array.new(256 * 240, 0x0F) }

      before { described_class.draw('LI', frame_buffer, left: 16, top: 8, colour: 0x30) }

      # L: the left column and the bottom row; I: the middle column, closed at the top and the bottom (5×7 in each
      # cell, from its second column). Columns 16 to 31 of rows 8 to 14, `#` where the colour was drawn.
      it "colours each character's glyph in its own cell" do
        symbols = { 0x30 => '#', 0x0F => '.' }
        drawn = (8..14).map { |row| frame_buffer[(row * 256) + 16, 16].map { symbols.fetch(it) }.join }

        expect(drawn).to eq(
          %w[
            .#........###...
            .#.........#....
            .#.........#....
            .#.........#....
            .#.........#....
            .#.........#....
            .#####....###...
          ]
        )
      end

      it 'leaves every other pixel as it was' do
        expect(frame_buffer.count(0x0F)).to eq((256 * 240) - 22)
      end
    end
  end

  describe '.printable' do
    context 'when the text has lower case letters' do
      it 'turns them to upper case' do
        expect(described_class.printable('Zelda')).to eq('ZELDA')
      end
    end

    context 'when it has letters with accents' do
      it 'drops the accents' do
        expect(described_class.printable('Pokémon Évora')).to eq('POKEMON EVORA')
      end
    end

    context 'when it has other characters without a glyph' do
      it 'shows each of them as a question mark' do
        expect(described_class.printable('Mario~Bros {beta}')).to eq('MARIO?BROS ?BETA?')
      end
    end
  end

  describe '.drawable?' do
    context 'when the character has a glyph' do
      it 'is true' do
        expect(described_class).to be_drawable('Q')
      end
    end

    context 'when the character has none' do
      it 'is false' do
        expect(described_class).not_to be_drawable('q')
      end
    end
  end
end
