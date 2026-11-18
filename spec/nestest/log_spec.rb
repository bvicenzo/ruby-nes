# frozen_string_literal: true

# Lines copied from nestest.log (other/nestest.log in the test ROM collection). The character before the mnemonic is
# a space for an official opcode and `*` for an unofficial one; the reduced form is Debug::Tracer's layout (plan 08,
# decision 5): no operand text, no PPU column, the marker kept (plan 09).
RSpec.describe Nestest::Log do
  describe '.lines' do
    context 'when the log is empty' do
      it 'is empty' do
        expect(described_class.lines('')).to be_empty
      end
    end

    context 'when the log has lines' do
      context 'and they are synthetic lines, official and unofficial' do
        let(:jump_line) do
          'C000  4C F5 C5  JMP $C5F5                       A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7'
        end
        let(:unofficial_line) do
          'C6BD  04 A9    *NOP $A9 = 00                    A:AA X:97 Y:4E P:EF SP:F9 PPU:128, 89 CYC:14579'
        end
        let(:no_operation_line) do
          'C6C3  EA        NOP                             A:AA X:97 Y:4E P:EF SP:F9 PPU:128,116 CYC:14588'
        end
        let(:branch_line) do
          'E083  D0 02     BNE $E087                       A:FF X:42 Y:00 P:27 SP:FB PPU: 87,333 CYC:10000'
        end
        let(:log_text) { "#{jump_line}\n#{unofficial_line}\n#{no_operation_line}\n#{branch_line}\n" }

        it 'reduces every line to the tracer layout, marker included' do
          expect(described_class.lines(log_text)).to eq(
            [
              'C000  4C F5 C5  JMP  A:00 X:00 Y:00 P:24 SP:FD CYC:7',
              'C6BD  04 A9    *NOP  A:AA X:97 Y:4E P:EF SP:F9 CYC:14579',
              'C6C3  EA        NOP  A:AA X:97 Y:4E P:EF SP:F9 CYC:14588',
              'E083  D0 02     BNE  A:FF X:42 Y:00 P:27 SP:FB CYC:10000'
            ]
          )
        end
      end

      context "and they are nestest.log's lines", test_rom: Nestest::LOG_PATH do
        let(:log_text) { File.read(test_rom_path(Nestest::LOG_PATH)) }

        it 'keeps all 8991 lines, the last one C66E RTS', :aggregate_failures do
          log_lines = described_class.lines(log_text)
          expect(log_lines.size).to eq(8991)
          expect(log_lines.last).to eq('C66E  60        RTS  A:00 X:FF Y:15 P:27 SP:FD CYC:26554')
        end
      end
    end
  end
end
