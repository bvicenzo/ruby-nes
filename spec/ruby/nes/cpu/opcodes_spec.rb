# frozen_string_literal: true

# The official opcodes (https://www.nesdev.org/wiki/Instruction_reference): 56 instructions over 151 opcodes. The other
# 105 bytes are unofficial opcodes (https://www.nesdev.org/wiki/CPU_unofficial_opcodes), left to plan 09.
RSpec.describe Ruby::Nes::Cpu::Opcodes do
  describe '::TABLE' do
    context 'when indexed by an unofficial opcode ($02)' do
      it 'has no entry' do
        expect(described_class::TABLE[0x02]).to be_nil
      end
    end

    context 'when indexed by an official opcode ($BD)' do
      it 'describes LDA, absolute,X, in 4 base cycles' do
        expect(described_class::TABLE[0xBD]).to have_attributes(mnemonic: 'LDA', mode: :absolute_x, cycles: 4)
      end
    end

    context 'when every entry is counted' do
      it 'holds 256 entries, 151 of them official', :aggregate_failures do
        expect(described_class::TABLE.size).to eq(256)
        expect(described_class::TABLE.compact.size).to eq(151)
      end
    end
  end
end
