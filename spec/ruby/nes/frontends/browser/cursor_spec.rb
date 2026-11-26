# frozen_string_literal: true

require 'ruby/nes/frontends/browser'

# The focus in the browser's list of ROMs and the rows of it shown (plan 37, scope 3): the focus starts on the first
# ROM, moves by rows or by pages of the rows shown, and stops at the first and the last ROM. The rows shown follow the
# focus, scrolling only as far as needed to keep it in sight. The list holds at least one ROM.
RSpec.describe Ruby::Nes::Frontends::Browser::Cursor do
  describe '#move' do
    context 'when the focus would pass the first ROM' do
      subject(:cursor) { described_class.new(size: 30, rows: 10) }

      before { cursor.move(2) }

      it 'stops on it' do
        cursor.move(-3)

        expect(cursor).to have_attributes(focus: 0, visible: 0...10)
      end
    end

    context 'when the focus would pass the last ROM' do
      subject(:cursor) { described_class.new(size: 30, rows: 10) }

      it 'stops on it, shown last' do
        cursor.move(31)

        expect(cursor).to have_attributes(focus: 29, visible: 20...30)
      end
    end

    context 'when the focus stays in the list' do
      context 'but leaves the rows shown below' do
        subject(:cursor) { described_class.new(size: 30, rows: 10) }

        before { cursor.move(9) }

        it 'scrolls them down until it is shown last' do
          cursor.move(2)

          expect(cursor).to have_attributes(focus: 11, visible: 2...12)
        end
      end

      context 'but leaves the rows shown above' do
        subject(:cursor) { described_class.new(size: 30, rows: 10) }

        before { cursor.move(20) }

        it 'scrolls them up until it is shown first' do
          cursor.move(-12)

          expect(cursor).to have_attributes(focus: 8, visible: 8...18)
        end
      end

      context 'and stays within the rows shown' do
        subject(:cursor) { described_class.new(size: 30, rows: 10) }

        before { cursor.move(20) }

        it 'keeps them' do
          cursor.move(-5)

          expect(cursor).to have_attributes(focus: 15, visible: 11...21)
        end
      end
    end
  end

  describe '#page' do
    context 'when a page would pass the last ROM' do
      subject(:cursor) { described_class.new(size: 15, rows: 10) }

      before { cursor.move(8) }

      it 'stops on it' do
        cursor.page(1)

        expect(cursor).to have_attributes(focus: 14, visible: 5...15)
      end
    end

    context 'when a page stays in the list' do
      subject(:cursor) { described_class.new(size: 30, rows: 10) }

      before { cursor.move(3) }

      it 'moves the focus by the rows shown' do
        cursor.page(1)

        expect(cursor).to have_attributes(focus: 13, visible: 4...14)
      end
    end
  end

  describe '#visible' do
    context 'when the list is shorter than the rows shown' do
      subject(:cursor) { described_class.new(size: 4, rows: 10) }

      it 'is the whole list' do
        expect(cursor.visible).to eq(0...4)
      end
    end

    context 'when the list is longer' do
      subject(:cursor) { described_class.new(size: 30, rows: 10) }

      it 'is as many ROMs as rows, from the first shown' do
        expect(cursor.visible).to eq(0...10)
      end
    end
  end
end
