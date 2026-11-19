# frozen_string_literal: true

# blargg's "Output at $6000" (the readme of every suite, e.g. instr_test-v5/readme.txt): "The test status is written to
# $6000. $80 means the test is running, $81 means the test needs the reset button pressed, but delayed by at least 100
# msec from now. $00-$7F means the test has completed and given that result code." "All text output is written
# starting at $6004, with a zero-byte terminator at the end." "$DE $B0 $G1 is written to $6001-$6003" so an emulator
# knows the data is valid; the ROMs store $DE, $B0 and $61 (`A9 61 8D 03 60` in instr_test-v5's 01-basics.nes).
RSpec.describe Blargg::Report do
  describe '#state' do
    subject(:report) { described_class.new(bus) }

    let(:bus) { FlatBus.new }

    context 'when the signature is missing' do
      before do
        bus.write_bytes(0x6000, [0x00, 0xDE, 0xB0, 0x60])
      end

      it 'is absent' do
        expect(report.state).to eq(:absent)
      end
    end

    context 'when the signature is there' do
      context 'and the status is $80' do
        before { bus.write_bytes(0x6000, [0x80, 0xDE, 0xB0, 0x61]) }

        it 'is running' do
          expect(report.state).to eq(:running)
        end
      end

      context 'and the status is $81' do
        before { bus.write_bytes(0x6000, [0x81, 0xDE, 0xB0, 0x61]) }

        it 'is a reset request' do
          expect(report.state).to eq(:reset_requested)
        end
      end

      context 'and the status is above $81' do
        before { bus.write_bytes(0x6000, [0x82, 0xDE, 0xB0, 0x61]) }

        it 'is running' do
          expect(report.state).to eq(:running)
        end
      end

      context 'and the status is $7F' do
        before { bus.write_bytes(0x6000, [0x7F, 0xDE, 0xB0, 0x61]) }

        it 'is finished' do
          expect(report.state).to eq(:finished)
        end
      end
    end
  end

  describe '#code' do
    subject(:report) { described_class.new(bus) }

    let(:bus) { FlatBus.new }

    before { bus.write_bytes(0x6000, [0x03, 0xDE, 0xB0, 0x61]) }

    it 'is the status byte' do
      expect(report.code).to eq(0x03)
    end
  end

  describe '#text' do
    subject(:report) { described_class.new(bus) }

    let(:bus) { FlatBus.new }

    context 'when a zero byte ends the text' do
      before { bus.write_bytes(0x6004, "Passed\n".bytes + [0x00, 0x41]) }

      it 'is the text before it' do
        expect(report.text).to eq("Passed\n")
      end
    end

    context 'when no zero byte comes before the end of PRG RAM' do
      before do
        bus.write_bytes(0x6004, Array.new(0x1FFC, 0x41))
        bus.write(0x8000, 0x00)
      end

      it 'stops at $7FFF' do
        expect(report.text.size).to eq(0x1FFC)
      end
    end
  end
end
