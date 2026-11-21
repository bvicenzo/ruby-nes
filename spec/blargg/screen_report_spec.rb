# frozen_string_literal: true

# blargg's older shell (cpu_dummy_reads, https://github.com/christopherpow/nes-test-roms) prints its result on screen
# only: its text console fills nametable 0 with tiles whose numbers are ASCII codes, 32 per row, one character of
# margin on the left, and ends with a line "Passed", "Failed" or "Error <code>". The rows are written here straight
# through the console's PPU bus ($2000 is row 0, $2020 row 1, https://www.nesdev.org/wiki/PPU_nametables).
RSpec.describe Blargg::ScreenReport do
  describe '#state' do
    subject(:report) { described_class.new(console) }

    let(:console) { Ruby::Nes::Console.new(Cartridges.build) }

    context 'when no line on screen is a result' do
      before do
        ' cpu_dummy_reads'.bytes.each_with_index { |byte, column| console.ppu_bus.write(0x2000 + column, byte) }
      end

      it 'is running' do
        expect(report.state).to eq(:running)
      end
    end

    context 'when a line on screen is a result' do
      before { ' Passed'.bytes.each_with_index { |byte, column| console.ppu_bus.write(0x2020 + column, byte) } }

      it 'is finished' do
        expect(report.state).to eq(:finished)
      end
    end
  end

  describe '#code' do
    subject(:report) { described_class.new(console) }

    let(:console) { Ruby::Nes::Console.new(Cartridges.build) }

    context 'when no line on screen is a result' do
      before do
        ' cpu_dummy_reads'.bytes.each_with_index { |byte, column| console.ppu_bus.write(0x2000 + column, byte) }
      end

      it 'is nil' do
        expect(report.code).to be_nil
      end
    end

    context 'when a line on screen is "Passed"' do
      before { ' Passed'.bytes.each_with_index { |byte, column| console.ppu_bus.write(0x2020 + column, byte) } }

      it 'is zero' do
        expect(report.code).to eq(0)
      end
    end

    context 'when a line on screen is "Failed"' do
      before { ' Failed'.bytes.each_with_index { |byte, column| console.ppu_bus.write(0x2020 + column, byte) } }

      it 'is one' do
        expect(report.code).to eq(1)
      end
    end

    context 'when a line on screen is "Error" and a code' do
      context 'and the code has no leading zero' do
        before { ' Error 3'.bytes.each_with_index { |byte, column| console.ppu_bus.write(0x2020 + column, byte) } }

        it 'is that code' do
          expect(report.code).to eq(3)
        end
      end

      context 'and the code has a leading zero' do
        before { ' Error 08'.bytes.each_with_index { |byte, column| console.ppu_bus.write(0x2020 + column, byte) } }

        it 'is that code, read as a decimal number' do
          expect(report.code).to eq(8)
        end
      end
    end
  end

  describe '#text' do
    subject(:report) { described_class.new(console) }

    let(:console) { Ruby::Nes::Console.new(Cartridges.build) }

    before do
      ' cpu_dummy_reads'.bytes.each_with_index { |byte, column| console.ppu_bus.write(0x2040 + column, byte) }
      ' Passed'.bytes.each_with_index { |byte, column| console.ppu_bus.write(0x2060 + column, byte) }
    end

    it 'is the rows with text, trimmed, one per line' do
      expect(report.text).to eq("cpu_dummy_reads\nPassed")
    end
  end
end
