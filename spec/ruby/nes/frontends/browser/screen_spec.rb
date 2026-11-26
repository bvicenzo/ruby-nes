# frozen_string_literal: true

require 'ruby/nes/frontends/browser'

# The ROM browser's screen (plan 37, decision 3): an NES frame of 256 × 240 palette indices, its text on the grid of
# 8 × 8 cells an NES draws its tiles on (32 columns, 30 rows), within lines 8-231 so `--crop-overscan` hides none of it.
# At the top, framed, the preview of the ROM in focus at half size (from line 9, cells 8-23); in its place, the reason
# the ROM cannot be run, when there is one, or "NO PREVIEW YET" while there is no picture. Under it, the focus's tags,
# cut to a row. Then, past a blank row, the list, 10 rows (19-28): the cursor on the focus, each name cut to 26 cells,
# grey when ruby-nes cannot run the ROM, a heart for a battery save and a star for save states, and arrows where the
# list goes on above or below. With no ROM, it says the folder has none.
RSpec.describe Ruby::Nes::Frontends::Browser::Screen do
  describe '#list' do
    context 'when the ROM in focus cannot be run' do
      subject(:screen) { described_class.new }

      let(:roms) { [BrowserRoms.build(name: 'CASTLEVANIA III', problem: 'MAPPER 5 IS NOT SUPPORTED')] }
      let(:cursor) { Ruby::Nes::Frontends::Screens::Cursor.new(size: 1, rows: 10) }

      it "shows the reason in the preview's place, in lines that fit" do
        rows = ScreenText.rows(screen.list(roms:, cursor:, preview_frame: nil, problem: 'MAPPER 5 IS NOT SUPPORTED'))

        expect(rows[7..8]).to eq(['       #MAPPER 5 IS NOT #       ', '       #   SUPPORTED    #       '])
      end
    end

    context 'when the ROM in focus can be run' do
      context 'but it has no picture yet' do
        subject(:screen) { described_class.new }

        let(:roms) { [BrowserRoms.build(name: 'CASTLEVANIA')] }
        let(:cursor) { Ruby::Nes::Frontends::Screens::Cursor.new(size: 1, rows: 10) }

        it "says so in the preview's place" do
          rows = ScreenText.rows(screen.list(roms:, cursor:, preview_frame: nil, problem: nil))

          expect(rows[8]).to eq('       # NO PREVIEW YET #       ')
        end
      end

      context 'and it has a picture' do
        subject(:screen) { described_class.new }

        let(:roms) { [BrowserRoms.build(name: 'CASTLEVANIA')] }
        let(:cursor) { Ruby::Nes::Frontends::Screens::Cursor.new(size: 1, rows: 10) }
        # Every pixel of a colour of its own along each row.
        let(:preview_frame) { Array.new(256 * 240) { it % 64 } }

        # One pixel in two of every other line, from 64, 9: 128 × 120.
        it "shows it at half size in the preview's place" do
          frame = screen.list(roms:, cursor:, preview_frame:, problem: nil)

          expect(Array.new(120) { |row| frame[((9 + row) * 256) + 64, 128] })
            .to eq(Array.new(120) { |row| Array.new(128) { |column| preview_frame[(row * 2 * 256) + (column * 2)] } })
        end

        it 'draws nothing on the lines an overscan crop hides, 0-7 and 232-239' do
          frame = screen.list(roms:, cursor:, preview_frame:, problem: nil)

          expect(frame[0, 8 * 256] + frame[232 * 256, 8 * 256]).to all(eq(described_class::BACKGROUND))
        end
      end
    end

    context 'when the list fits in its rows' do
      subject(:screen) { described_class.new }

      let(:roms) do
        [
          BrowserRoms.build(name: 'BOMBERMAN II'),
          BrowserRoms.build(name: 'LEGEND OF ZELDA, THE', tags: '(USA) (REV 1)', battery_save: true, save_states: true),
          BrowserRoms.build(name: 'MARIO BROS.', save_states: true)
        ]
      end
      let(:cursor) { Ruby::Nes::Frontends::Screens::Cursor.new(size: 3, rows: 10).tap { it.move(1) } }

      it "shows the focus's tags, each ROM with its marks and the cursor on the focus, with no arrows" do
        rows = ScreenText.rows(screen.list(roms:, cursor:, preview_frame: nil, problem: nil))

        expect(rows[17..22]).to eq(
          [
            '         (USA) (REV 1)          ',
            '                                ',
            '  BOMBERMAN II                  ',
            ' ▶LEGEND OF ZELDA, THE      ♥★  ',
            '  MARIO BROS.                ★  ',
            '                                '
          ]
        )
      end
    end

    context 'when the list is longer than its rows' do
      context 'and the rows shown start at the first ROM' do
        subject(:screen) { described_class.new }

        let(:roms) { Array.new(15) { BrowserRoms.build(name: "GAME #{it + 1}") } }
        let(:cursor) { Ruby::Nes::Frontends::Screens::Cursor.new(size: 15, rows: 10) }

        it 'points down from the last row shown' do
          rows = ScreenText.rows(screen.list(roms:, cursor:, preview_frame: nil, problem: nil))

          expect(rows.values_at(19, 28)).to eq([' ▶GAME 1                        ', '  GAME 10                     ▼ '])
        end
      end

      context 'and they end at the last ROM' do
        subject(:screen) { described_class.new }

        let(:roms) { Array.new(15) { BrowserRoms.build(name: "GAME #{it + 1}") } }
        let(:cursor) { Ruby::Nes::Frontends::Screens::Cursor.new(size: 15, rows: 10).tap { it.move(14) } }

        it 'points up from the first row shown' do
          rows = ScreenText.rows(screen.list(roms:, cursor:, preview_frame: nil, problem: nil))

          expect(rows.values_at(19, 28)).to eq(['  GAME 6                      ▲ ', ' ▶GAME 15                       '])
        end
      end

      context 'and they are in between' do
        subject(:screen) { described_class.new }

        let(:roms) { Array.new(20) { BrowserRoms.build(name: "GAME #{it + 1}") } }
        let(:cursor) { Ruby::Nes::Frontends::Screens::Cursor.new(size: 20, rows: 10).tap { it.move(15) } }

        it 'points both ways' do
          rows = ScreenText.rows(screen.list(roms:, cursor:, preview_frame: nil, problem: nil))

          expect(rows.values_at(19, 28)).to eq(['  GAME 7                      ▲ ', ' ▶GAME 16                     ▼ '])
        end
      end
    end

    context "when the focus's tags are longer than a row" do
      subject(:screen) { described_class.new }

      let(:roms) { [BrowserRoms.build(name: 'MEGA MAN 3', tags: '(USA, EUROPE) (REV A) (VIRTUAL CONSOLE)')] }
      let(:cursor) { Ruby::Nes::Frontends::Screens::Cursor.new(size: 1, rows: 10) }

      it 'cuts them to fit', :aggregate_failures do
        rows = ScreenText.rows(screen.list(roms:, cursor:, preview_frame: nil, problem: nil))

        expect(rows[17]).to eq('(USA, EUROPE) (REV A) (VIRTUAL C')
        expect(rows[16]).to eq('       ##################       ')
      end
    end

    context 'when a ROM in the list cannot be run' do
      subject(:screen) { described_class.new }

      let(:roms) do
        [BrowserRoms.build(name: 'CASTLEVANIA'), BrowserRoms.build(name: 'CASTLEVANIA III', problem: 'MAPPER 5')]
      end
      let(:cursor) { Ruby::Nes::Frontends::Screens::Cursor.new(size: 2, rows: 10) }

      it 'shows its name in grey' do
        frame = screen.list(roms:, cursor:, preview_frame: nil, problem: nil)

        expect(Array.new(8) { |line| frame[((20 * 8) + line) * 256, 256] }.flatten.uniq)
          .to contain_exactly(described_class::BACKGROUND, described_class::QUIET)
      end
    end

    context 'when a name is longer than its row' do
      subject(:screen) { described_class.new }

      let(:roms) do
        [BrowserRoms.build(name: 'BOMBERMAN II'), BrowserRoms.build(name: 'SUPER MARIO BROS. 3 - THE ADVENTURE')]
      end
      let(:cursor) { Ruby::Nes::Frontends::Screens::Cursor.new(size: 2, rows: 10) }

      it 'cuts it to fit' do
        rows = ScreenText.rows(screen.list(roms:, cursor:, preview_frame: nil, problem: nil))

        expect(rows[20]).to eq('  SUPER MARIO BROS. 3 - THE     ')
      end
    end
  end

  describe '#empty' do
    context 'when the folder is short enough for a row' do
      subject(:screen) { described_class.new }

      it 'says it holds no ROMs, naming it in what the font prints', :aggregate_failures do
        rows = ScreenText.rows(screen.empty('/home/player/roms'))

        expect(rows[13]).to eq('           NO ROMS IN           ')
        expect(rows[15]).to eq('       /HOME/PLAYER/ROMS        ')
      end
    end

    context 'when it is longer' do
      subject(:screen) { described_class.new }

      it 'names its last 30 characters' do
        rows = ScreenText.rows(screen.empty('/home/player/games/nintendo/entertainment/system'))

        expect(rows[15]).to eq(' /NINTENDO/ENTERTAINMENT/SYSTEM ')
      end
    end
  end
end
