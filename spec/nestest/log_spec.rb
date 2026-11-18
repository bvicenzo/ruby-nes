# frozen_string_literal: true

# Lines copied from nestest.log (other/nestest.log in the test ROM collection). The character before the mnemonic is
# a space for an official opcode and `*` for an unofficial one; the reduced form is Debug::Tracer's layout (plan 08,
# decision 5): no operand text, no PPU column.
RSpec.describe Nestest::Log do
  describe '.official_lines' do
    context 'when the log is empty' do
      it 'is empty' do
        expect(described_class.official_lines('')).to be_empty
      end
    end

    context 'when the log has lines' do
      let(:unofficial_line) do
        'C6BD  04 A9    *NOP $A9 = 00                    A:AA X:97 Y:4E P:EF SP:F9 PPU:128, 89 CYC:14579'
      end
      let(:jump_line) do
        'C000  4C F5 C5  JMP $C5F5                       A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7'
      end

      context 'but the first one is unofficial' do
        let(:log_text) { "#{unofficial_line}\n#{jump_line}\n" }

        it 'is empty' do
          expect(described_class.official_lines(log_text)).to be_empty
        end
      end

      context 'and it starts with official lines' do
        context 'and an unofficial line follows them' do
          context 'and they are synthetic lines' do
            let(:no_operation_line) do
              'C6C3  EA        NOP                             A:AA X:97 Y:4E P:EF SP:F9 PPU:128,116 CYC:14588'
            end
            let(:log_text) { "#{jump_line}\n#{unofficial_line}\n#{no_operation_line}\n" }

            it 'stops before the unofficial line' do
              expect(described_class.official_lines(log_text))
                .to eq(['C000  4C F5 C5  JMP  A:00 X:00 Y:00 P:24 SP:FD CYC:7'])
            end
          end

          # The first unofficial line of the real log is line 5004, `C6BD  04 A9    *NOP`.
          context "and they are nestest.log's lines", test_rom: Nestest::LOG_PATH do
            let(:log_text) { File.read(test_rom_path(Nestest::LOG_PATH)) }

            it 'keeps the 5003 lines before the first unofficial opcode', :aggregate_failures do
              official_lines = described_class.official_lines(log_text)
              expect(official_lines.size).to eq(5003)
              expect(official_lines.last).to eq('C6BC  28        PLP  A:AA X:97 Y:4E P:A5 SP:F8 CYC:14575')
            end
          end
        end

        context 'and every line is official' do
          let(:load_line) do
            'C5F5  A2 00     LDX #$00                        A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 30 CYC:10'
          end
          let(:no_operation_line) do
            'C72D  EA        NOP                             A:00 X:00 Y:00 P:26 SP:FB PPU:  0, 81 CYC:27'
          end
          let(:branch_line) do
            'E083  D0 02     BNE $E087                       A:FF X:42 Y:00 P:27 SP:FB PPU: 87,333 CYC:10000'
          end
          let(:log_text) { "#{jump_line}\n#{load_line}\n#{no_operation_line}\n#{branch_line}\n" }

          it 'reduces every line to the tracer layout' do
            expect(described_class.official_lines(log_text)).to eq(
              [
                'C000  4C F5 C5  JMP  A:00 X:00 Y:00 P:24 SP:FD CYC:7',
                'C5F5  A2 00     LDX  A:00 X:00 Y:00 P:24 SP:FD CYC:10',
                'C72D  EA        NOP  A:00 X:00 Y:00 P:26 SP:FB CYC:27',
                'E083  D0 02     BNE  A:FF X:42 Y:00 P:27 SP:FB CYC:10000'
              ]
            )
          end
        end
      end
    end
  end
end
