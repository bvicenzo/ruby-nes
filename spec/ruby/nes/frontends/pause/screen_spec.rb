# frozen_string_literal: true

require 'ruby/nes/frontends/pause'

# The pause menu's screens (plan 38), NES frames of 256 × 240 palette indices on the 8 × 8 grid, as the ROM browser's
# (plan 37, decision 3), everything within lines 8-231 (https://www.nesdev.org/wiki/Overscan).
#
# - The menu: the picture given (the paused game, dimmed) with a box over it, 16 columns wide (8-23) and centred,
#   framed by a line of grey just outside it; in it the title, a blank row, then the entries, the cursor on the focus,
#   each in white, or grey when it cannot be chosen.
# - The slot picker: as the browser's list, the picture of the slot in focus at half size and framed at the top, or
#   EMPTY in its place; the title under it; the slots in rows 19-28, the cursor on the focus, a star for a slot with a
#   state, each in white, or grey when it cannot be chosen.
RSpec.describe Ruby::Nes::Frontends::Pause::Screen do
  describe '#menu' do
    context 'when the background is a picture' do
      subject(:screen) { described_class.new }

      let(:background) { Array.new(256 * 240, 0x06) }
      let(:choices) { Ruby::Nes::Frontends::Screens::Choices.new(entries: %i[resume quit]) }

      it 'shows it around the box', :aggregate_failures do
        frame = screen.menu(background:, title: 'PAUSED', choices:, labels: { resume: 'RESUME', quit: 'QUIT' })

        expect(frame[0, 256 * 8 * 10]).to all(eq(0x06))
        expect(ScreenText.colours(frame, row: 14, columns: 0...7)).to eq([0x06])
      end
    end

    context 'when the box is drawn' do
      subject(:screen) { described_class.new }

      let(:background) { Array.new(256 * 240, 0x0F) }
      let(:choices) do
        Ruby::Nes::Frontends::Screens::Choices.new(entries: %i[resume load_state quit], unavailable: [:load_state])
      end
      let(:labels) { { resume: 'RESUME', load_state: 'LOAD STATE', quit: 'QUIT' } }

      it 'draws the box framed, its title, the entries and the cursor on the focus' do
        rows = ScreenText.rows(screen.menu(background:, title: 'PAUSED', choices:, labels:))

        expect(rows[10..18]).to eq(
          [
            '       ##################       ',
            '       #                #       ',
            '       #     PAUSED     #       ',
            '       #                #       ',
            '       # ▶RESUME        #       ',
            '       #  LOAD STATE    #       ',
            '       #  QUIT          #       ',
            '       #                #       ',
            '       ##################       '
          ]
        )
      end
    end

    context 'when its entries are drawn' do
      subject(:screen) { described_class.new }

      let(:background) { Array.new(256 * 240, 0x0F) }
      let(:choices) do
        Ruby::Nes::Frontends::Screens::Choices.new(entries: %i[resume load_state quit], unavailable: [:load_state])
      end
      let(:labels) { { resume: 'RESUME', load_state: 'LOAD STATE', quit: 'QUIT' } }

      context 'and an entry cannot be chosen' do
        it 'is grey' do
          frame = screen.menu(background:, title: 'PAUSED', choices:, labels:)

          expect(ScreenText.colours(frame, row: 15, columns: 10...20)).to eq([0x10])
        end
      end

      context 'and an entry can be chosen' do
        it 'is white' do
          frame = screen.menu(background:, title: 'PAUSED', choices:, labels:)

          expect(ScreenText.colours(frame, row: 16, columns: 10...20)).to eq([0x30])
        end
      end
    end
  end

  describe '#slots' do
    context 'when the slot in focus has no picture' do
      subject(:screen) { described_class.new }

      let(:choices) { Ruby::Nes::Frontends::Screens::Choices.new(entries: (0..9).to_a) }

      it "says it is empty in the picture's place" do
        rows = ScreenText.rows(screen.slots(title: 'SAVE STATE', choices:, written: [], picture: nil))

        expect(rows[8]).to eq('       #     EMPTY      #       ')
      end
    end

    context 'when the slot in focus has a picture' do
      subject(:screen) { described_class.new }

      let(:choices) { Ruby::Nes::Frontends::Screens::Choices.new(entries: (0..9).to_a) }
      # Every pixel of a colour of its own along each row.
      let(:picture) { Array.new(256 * 240) { it % 64 } }

      # One pixel in two of every other line, from 64, 9: 128 × 120.
      it 'shows it at half size at the top' do
        frame = screen.slots(title: 'SAVE STATE', choices:, written: [0], picture:)

        expect(Array.new(120) { |row| frame[((9 + row) * 256) + 64, 128] })
          .to eq(Array.new(120) { |row| Array.new(128) { |column| picture[(row * 2 * 256) + (column * 2)] } })
      end
    end

    context 'when the slots are listed' do
      subject(:screen) { described_class.new }

      let(:choices) do
        Ruby::Nes::Frontends::Screens::Choices.new(entries: (0..9).to_a, unavailable: [0, *4..9], focus: 2)
      end

      it 'draws the title, the slots, a star on those with a state and the cursor on the focus' do
        rows = ScreenText.rows(screen.slots(title: 'LOAD STATE', choices:, written: [1, 2, 3], picture: nil))

        expect(rows[17..28]).to eq(
          [
            '           LOAD STATE           ',
            '                                ',
            '  SLOT 0                        ',
            '  SLOT 1                     ★  ',
            ' ▶SLOT 2                     ★  ',
            '  SLOT 3                     ★  ',
            '  SLOT 4                        ',
            '  SLOT 5                        ',
            '  SLOT 6                        ',
            '  SLOT 7                        ',
            '  SLOT 8                        ',
            '  SLOT 9                        '
          ]
        )
      end
    end

    context 'when its slots are drawn' do
      subject(:screen) { described_class.new }

      let(:choices) do
        Ruby::Nes::Frontends::Screens::Choices.new(entries: (0..9).to_a, unavailable: [0, *4..9], focus: 2)
      end

      context 'and a slot cannot be chosen' do
        it 'is grey' do
          frame = screen.slots(title: 'LOAD STATE', choices:, written: [1, 2, 3], picture: nil)

          expect(ScreenText.colours(frame, row: 19, columns: 2...8)).to eq([0x10])
        end
      end

      context 'and a slot can be chosen' do
        it 'is white' do
          frame = screen.slots(title: 'LOAD STATE', choices:, written: [1, 2, 3], picture: nil)

          expect(ScreenText.colours(frame, row: 20, columns: 2...8)).to eq([0x30])
        end
      end
    end
  end
end
