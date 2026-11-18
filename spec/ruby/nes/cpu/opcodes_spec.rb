# frozen_string_literal: true

# The official opcodes (https://www.nesdev.org/wiki/Instruction_reference): 56 instructions over 151 opcodes. The other
# 105 bytes are unofficial opcodes (https://www.nesdev.org/wiki/CPU_unofficial_opcodes), named after the wiki's opcode
# matrix except ISB (nestest.log's name) and JAM (6502_cpu.txt: "Jams the machine"); their cycles come from
# https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes ("LAX d" and "SBC #i" among them).
RSpec.describe Ruby::Nes::Cpu::Opcodes do
  describe '::TABLE' do
    context 'when indexed by an official opcode ($BD)' do
      it 'describes LDA, absolute,X, in 4 base cycles, official' do
        expect(described_class::TABLE[0xBD])
          .to have_attributes(mnemonic: 'LDA', mode: :absolute_x, cycles: 4, official?: true)
      end
    end

    context 'when indexed by an unofficial opcode that reads ($A7)' do
      it 'describes LAX, zero page, in 3 base cycles, unofficial' do
        expect(described_class::TABLE[0xA7])
          .to have_attributes(mnemonic: 'LAX', mode: :zero_page, cycles: 3, official?: false)
      end
    end

    context 'when indexed by the unofficial twin of an official opcode ($EB)' do
      it 'describes SBC, immediate, in 2 base cycles, unofficial' do
        expect(described_class::TABLE[0xEB])
          .to have_attributes(mnemonic: 'SBC', mode: :immediate, cycles: 2, official?: false)
      end
    end

    context 'when indexed by a jam opcode ($02)' do
      it 'describes JAM, implied, unofficial' do
        expect(described_class::TABLE[0x02]).to have_attributes(mnemonic: 'JAM', mode: :implied, official?: false)
      end
    end

    context 'when every entry is counted' do
      it 'holds 256 entries, 151 official and 105 unofficial', :aggregate_failures do
        expect(described_class::TABLE.compact.size).to eq(256)
        expect(described_class::TABLE.count(&:official?)).to eq(151)
        expect(described_class::TABLE.count { |opcode| !opcode.official? }).to eq(105)
      end
    end
  end

  describe 'Opcode#official?' do
    context 'when the opcode is built without saying whether it is official' do
      subject(:opcode) { described_class::Opcode.new(mnemonic: 'NOP', mode: :implied, cycles: 2) }

      it 'is official' do
        expect(opcode).to be_official
      end
    end

    context 'when the opcode is built as unofficial' do
      subject(:opcode) { described_class::Opcode.new(mnemonic: 'NOP', mode: :zero_page, cycles: 3, official: false) }

      it 'is not official' do
        expect(opcode).not_to be_official
      end
    end
  end

  # Operand sizes from https://www.nesdev.org/wiki/CPU_addressing_modes: "d" modes take an 8-bit operand, "a" modes a
  # 16-bit one, and implied has "no address operand" (accumulator names the A register, not a byte of the instruction).
  describe 'Opcode#size' do
    subject(:opcode) { described_class::Opcode.new(mnemonic:, mode:, cycles:) }

    let(:mnemonic) { 'NOP' }
    let(:cycles) { 2 }

    context 'when the mode is not in OPERAND_SIZES' do
      let(:mode) { :absolute_z }

      it 'raises KeyError' do
        expect { opcode.size }.to raise_error(KeyError)
      end
    end

    context 'when the mode is implied' do
      let(:mode) { :implied }

      it 'is 1 byte' do
        expect(opcode.size).to eq(1)
      end
    end

    context 'when the mode is accumulator' do
      let(:mode) { :accumulator }

      it 'is 1 byte' do
        expect(opcode.size).to eq(1)
      end
    end

    context 'when the mode is immediate' do
      let(:mode) { :immediate }

      it 'is 2 bytes' do
        expect(opcode.size).to eq(2)
      end
    end

    context 'when the mode is zero_page' do
      let(:mode) { :zero_page }

      it 'is 2 bytes' do
        expect(opcode.size).to eq(2)
      end
    end

    context 'when the mode is zero_page_x' do
      let(:mode) { :zero_page_x }

      it 'is 2 bytes' do
        expect(opcode.size).to eq(2)
      end
    end

    context 'when the mode is zero_page_y' do
      let(:mode) { :zero_page_y }

      it 'is 2 bytes' do
        expect(opcode.size).to eq(2)
      end
    end

    context 'when the mode is relative' do
      let(:mode) { :relative }

      it 'is 2 bytes' do
        expect(opcode.size).to eq(2)
      end
    end

    context 'when the mode is indexed_indirect' do
      let(:mode) { :indexed_indirect }

      it 'is 2 bytes' do
        expect(opcode.size).to eq(2)
      end
    end

    context 'when the mode is indirect_indexed' do
      let(:mode) { :indirect_indexed }

      it 'is 2 bytes' do
        expect(opcode.size).to eq(2)
      end
    end

    context 'when the mode is absolute' do
      let(:mode) { :absolute }

      it 'is 3 bytes' do
        expect(opcode.size).to eq(3)
      end
    end

    context 'when the mode is absolute_x' do
      let(:mode) { :absolute_x }

      it 'is 3 bytes' do
        expect(opcode.size).to eq(3)
      end
    end

    context 'when the mode is absolute_y' do
      let(:mode) { :absolute_y }

      it 'is 3 bytes' do
        expect(opcode.size).to eq(3)
      end
    end

    context 'when the mode is indirect' do
      let(:mode) { :indirect }

      it 'is 3 bytes' do
        expect(opcode.size).to eq(3)
      end
    end

    context 'when asked of every table entry' do
      let(:table_modes) { described_class::TABLE.map(&:mode).uniq }

      it 'finds an operand size for each one' do
        expect(described_class::OPERAND_SIZES.keys).to include(*table_modes)
      end
    end
  end
end
