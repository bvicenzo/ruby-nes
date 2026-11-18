# frozen_string_literal: true

RSpec.describe Nestest::Divergence do
  describe '#message' do
    subject(:divergence) do
      described_class.new(
        line_number: 2,
        expected: 'C001  EA        NOP  A:00 X:00 Y:00 P:20 SP:00 CYC:3',
        actual: 'C001  EA        NOP  A:00 X:00 Y:00 P:20 SP:00 CYC:2'
      )
    end

    it 'names the log line and shows both lines aligned' do
      expect(divergence.message).to eq(<<~MESSAGE)
        nestest.log line 2 differs:
          expected: C001  EA        NOP  A:00 X:00 Y:00 P:20 SP:00 CYC:3
          actual:   C001  EA        NOP  A:00 X:00 Y:00 P:20 SP:00 CYC:2
      MESSAGE
    end
  end
end
