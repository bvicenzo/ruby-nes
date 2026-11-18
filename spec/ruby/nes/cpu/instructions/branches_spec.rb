# frozen_string_literal: true

# Branches (https://www.nesdev.org/wiki/Instruction_reference): "2 (3 if branch taken, 4 if page crossed)" cycles; the
# offset is "relative to the first byte _after_ the branch instruction", so the page compared with the target's is the
# page of the program counter after the operand (where Cpu#relative_address leaves it). Each branch is given the
# target relative_address resolved; base cycles are charged by Cpu#step, so here only the extra ones are counted.
RSpec.describe Ruby::Nes::Cpu::Instructions::Branches do
  describe '#take_branch' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, program_counter:) }

    context 'when the target is on the same page, forward' do
      let(:program_counter) { 0x80F0 }

      it 'moves the program counter to the target' do
        cpu.take_branch(0x80FF)
        expect(cpu.program_counter).to eq(0x80FF)
      end

      it 'adds one cycle' do
        expect { cpu.take_branch(0x80FF) }.to change(cpu, :cycles).by(1)
      end
    end

    context 'when the target is on the same page, backward' do
      let(:program_counter) { 0x8020 }

      it 'adds one cycle' do
        expect { cpu.take_branch(0x8000) }.to change(cpu, :cycles).by(1)
      end
    end

    context 'when the target is on the next page' do
      let(:program_counter) { 0x80F0 }

      it 'moves the program counter to the target' do
        cpu.take_branch(0x8100)
        expect(cpu.program_counter).to eq(0x8100)
      end

      it 'adds two cycles' do
        expect { cpu.take_branch(0x8100) }.to change(cpu, :cycles).by(2)
      end
    end

    context 'when the target is on the previous page' do
      let(:program_counter) { 0x8100 }

      it 'adds two cycles' do
        expect { cpu.take_branch(0x80FF) }.to change(cpu, :cycles).by(2)
      end
    end
  end

  describe '#branch_if_carry_clear' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, program_counter: 0x8002) }

    context 'when carry is set' do
      before { cpu.status.restore(0x01) }

      it 'leaves the program counter and the cycles unchanged', :aggregate_failures do
        cpu.branch_if_carry_clear(0x8010)
        expect(cpu.program_counter).to eq(0x8002)
        expect(cpu.cycles).to eq(0)
      end
    end

    context 'when carry is clear' do
      it 'moves the program counter to the target' do
        cpu.branch_if_carry_clear(0x8010)
        expect(cpu.program_counter).to eq(0x8010)
      end
    end
  end

  describe '#branch_if_carry_set' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, program_counter: 0x8002) }

    context 'when carry is clear' do
      it 'leaves the program counter and the cycles unchanged', :aggregate_failures do
        cpu.branch_if_carry_set(0x8010)
        expect(cpu.program_counter).to eq(0x8002)
        expect(cpu.cycles).to eq(0)
      end
    end

    context 'when carry is set' do
      before { cpu.status.restore(0x01) }

      it 'moves the program counter to the target' do
        cpu.branch_if_carry_set(0x8010)
        expect(cpu.program_counter).to eq(0x8010)
      end
    end
  end

  describe '#branch_if_equal' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, program_counter: 0x8002) }

    context 'when zero is clear' do
      it 'leaves the program counter and the cycles unchanged', :aggregate_failures do
        cpu.branch_if_equal(0x8010)
        expect(cpu.program_counter).to eq(0x8002)
        expect(cpu.cycles).to eq(0)
      end
    end

    context 'when zero is set' do
      before { cpu.status.restore(0x02) }

      it 'moves the program counter to the target' do
        cpu.branch_if_equal(0x8010)
        expect(cpu.program_counter).to eq(0x8010)
      end
    end
  end

  describe '#branch_if_not_equal' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, program_counter: 0x8002) }

    context 'when zero is set' do
      before { cpu.status.restore(0x02) }

      it 'leaves the program counter and the cycles unchanged', :aggregate_failures do
        cpu.branch_if_not_equal(0x8010)
        expect(cpu.program_counter).to eq(0x8002)
        expect(cpu.cycles).to eq(0)
      end
    end

    context 'when zero is clear' do
      it 'moves the program counter to the target' do
        cpu.branch_if_not_equal(0x8010)
        expect(cpu.program_counter).to eq(0x8010)
      end
    end
  end

  describe '#branch_if_minus' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, program_counter: 0x8002) }

    context 'when negative is clear' do
      it 'leaves the program counter and the cycles unchanged', :aggregate_failures do
        cpu.branch_if_minus(0x8010)
        expect(cpu.program_counter).to eq(0x8002)
        expect(cpu.cycles).to eq(0)
      end
    end

    context 'when negative is set' do
      before { cpu.status.restore(0x80) }

      it 'moves the program counter to the target' do
        cpu.branch_if_minus(0x8010)
        expect(cpu.program_counter).to eq(0x8010)
      end
    end
  end

  describe '#branch_if_plus' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, program_counter: 0x8002) }

    context 'when negative is set' do
      before { cpu.status.restore(0x80) }

      it 'leaves the program counter and the cycles unchanged', :aggregate_failures do
        cpu.branch_if_plus(0x8010)
        expect(cpu.program_counter).to eq(0x8002)
        expect(cpu.cycles).to eq(0)
      end
    end

    context 'when negative is clear' do
      it 'moves the program counter to the target' do
        cpu.branch_if_plus(0x8010)
        expect(cpu.program_counter).to eq(0x8010)
      end
    end
  end

  describe '#branch_if_overflow_clear' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, program_counter: 0x8002) }

    context 'when overflow is set' do
      before { cpu.status.restore(0x40) }

      it 'leaves the program counter and the cycles unchanged', :aggregate_failures do
        cpu.branch_if_overflow_clear(0x8010)
        expect(cpu.program_counter).to eq(0x8002)
        expect(cpu.cycles).to eq(0)
      end
    end

    context 'when overflow is clear' do
      it 'moves the program counter to the target' do
        cpu.branch_if_overflow_clear(0x8010)
        expect(cpu.program_counter).to eq(0x8010)
      end
    end
  end

  describe '#branch_if_overflow_set' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, program_counter: 0x8002) }

    context 'when overflow is clear' do
      it 'leaves the program counter and the cycles unchanged', :aggregate_failures do
        cpu.branch_if_overflow_set(0x8010)
        expect(cpu.program_counter).to eq(0x8002)
        expect(cpu.cycles).to eq(0)
      end
    end

    context 'when overflow is set' do
      before { cpu.status.restore(0x40) }

      it 'moves the program counter to the target' do
        cpu.branch_if_overflow_set(0x8010)
        expect(cpu.program_counter).to eq(0x8010)
      end
    end
  end
end
