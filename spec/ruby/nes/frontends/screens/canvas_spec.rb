# frozen_string_literal: true

require 'ruby/nes/frontends/screens'

# What the menus draw with (plan 38, out of plan 37's Browser::Screen): one NES frame of 256 × 240 palette indices
# (docs/architecture.md, Frame buffer contract), kept for the canvas's life, with its text on the grid of 8 × 8 cells
# an NES draws its tiles on (32 columns, 30 rows). It is cleared to a background colour or takes another frame's pixels,
# draws text from a cell or centred in a row or within some of its columns, fills an area, frames one with a line just outside it, and draws another
# frame scaled down. Nothing is drawn outside what each call names.
RSpec.describe Ruby::Nes::Frontends::Screens::Canvas do
  describe '#clear' do
    subject(:canvas) { described_class.new(background: 0x0F) }

    before { canvas.fill(left: 0, top: 0, width: 256, height: 240, colour: 0x30) }

    it 'paints every pixel the background' do
      canvas.clear

      expect(canvas.frame_buffer).to eq(Array.new(256 * 240, 0x0F))
    end
  end

  describe '#copy' do
    subject(:canvas) { described_class.new(background: 0x0F) }

    let(:game_frame) { Array.new(256 * 240) { it % 64 } }

    it "takes the frame's pixels into its own frame buffer, leaving the frame given apart", :aggregate_failures do
      frame_buffer = canvas.frame_buffer
      canvas.copy(game_frame)
      canvas.clear

      expect(canvas.frame_buffer).to be(frame_buffer)
      expect(game_frame).to eq(Array.new(256 * 240) { it % 64 })
    end
  end

  describe '#text' do
    subject(:canvas) { described_class.new(background: 0x0F) }

    it 'draws the text from the cell given' do
      canvas.text('RESUME', column: 3, row: 10, colour: 0x30)

      expect(ScreenText.rows(canvas.frame_buffer)[10]).to eq('   RESUME                       ')
    end
  end

  describe '#centred' do
    subject(:canvas) { described_class.new(background: 0x0F) }

    context 'when the text leaves an even number of columns' do
      it 'leaves as many on each side' do
        canvas.centred('PAUSED', row: 5, colour: 0x30)

        expect(ScreenText.rows(canvas.frame_buffer)[5]).to eq('             PAUSED             ')
      end
    end

    context 'when the text leaves an odd number of columns' do
      it 'leaves the one more on the right' do
        canvas.centred('QUIT!', row: 5, colour: 0x30)

        expect(ScreenText.rows(canvas.frame_buffer)[5]).to eq('             QUIT!              ')
      end
    end

    context 'when columns are given' do
      it 'centres it within them' do
        canvas.centred('EMPTY', row: 8, colour: 0x10, columns: 8...24)

        expect(ScreenText.rows(canvas.frame_buffer)[8]).to eq('             EMPTY              ')
      end
    end
  end

  describe '#fill' do
    subject(:canvas) { described_class.new(background: 0x0F) }

    it 'paints the area, nothing around it' do
      canvas.fill(left: 2, top: 1, width: 3, height: 2, colour: 0x16)

      expect(Array.new(4) { |row| canvas.frame_buffer[row * 256, 6] })
        .to eq([[0x0F] * 6, [0x0F, 0x0F, 0x16, 0x16, 0x16, 0x0F], [0x0F, 0x0F, 0x16, 0x16, 0x16, 0x0F], [0x0F] * 6])
    end
  end

  describe '#frame' do
    subject(:canvas) { described_class.new(background: 0x0F) }

    it 'draws a line one pixel outside the area, nothing inside it' do
      canvas.frame(left: 2, top: 2, width: 2, height: 1, colour: 0x10)

      expect(Array.new(5) { |row| canvas.frame_buffer[row * 256, 6] }).to eq(
        [
          [0x0F] * 6,
          [0x0F, 0x10, 0x10, 0x10, 0x10, 0x0F],
          [0x0F, 0x10, 0x0F, 0x0F, 0x10, 0x0F],
          [0x0F, 0x10, 0x10, 0x10, 0x10, 0x0F],
          [0x0F] * 6
        ]
      )
    end
  end

  describe '#picture' do
    subject(:canvas) { described_class.new(background: 0x0F) }

    # Every pixel of a colour of its own along each row.
    let(:game_frame) { Array.new(256 * 240) { it % 64 } }

    # One pixel in two of every other line, from 64, 9: 128 × 120.
    it 'draws one pixel in two of one line in two from the corner given, nothing around it', :aggregate_failures do
      canvas.picture(game_frame, left: 64, top: 9, scale: 2)

      expect(Array.new(120) { |row| canvas.frame_buffer[((9 + row) * 256) + 64, 128] })
        .to eq(Array.new(120) { |row| Array.new(128) { |column| game_frame[(row * 2 * 256) + (column * 2)] } })
      expect(canvas.frame_buffer[(8 * 256) + 64, 128] + canvas.frame_buffer[(129 * 256) + 64, 128])
        .to all(eq(0x0F))
    end
  end
end
