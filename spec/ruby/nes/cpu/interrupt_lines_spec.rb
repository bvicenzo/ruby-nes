# frozen_string_literal: true

# The arbiter of the CPU's two interrupt inputs (https://www.nesdev.org/wiki/CPU_interrupts): the NMI edge
# (Cpu::NmiDetector) and the IRQ level (Cpu::IrqLine). The CPU polls "the status of the interrupt lines at the end of
# the second-to-last cycle" of an instruction: a poll at the start of a step on `cycle` sees the changes that came
# before `cycle - 1`. "If both an NMI and an IRQ are pending at the end of an instruction, the NMI will be handled";
# the IRQ is masked by the I the poll sees, and stays as long as its line.
#
# Plan 22 adds the poll's exceptions: "The CLI, SEI, and PLP instructions on the other hand change the I flag after
# polling for interrupts", so the poll that follows them sees the I from before them; a taken branch that does not
# cross a page polls "before the second CPU cycle" and not before the third, one cycle earlier than usual; BRK and the
# interrupt sequence pick their vector after tick 4, so an NMI by then hijacks them ("an NMI can hijack an IRQ"); and
# the interrupt sequences do not poll, so the handler's first instruction runs before another interrupt.
RSpec.describe Ruby::Nes::Cpu::InterruptLines do
  describe '#acknowledge' do
    context 'when neither line is seen by the poll' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.nmi_line_changed(true, 9)
          lines.assert_irq(described_class::MAPPER_IRQ, 9)
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'returns nothing' do
        expect(interrupt_lines.acknowledge(10)).to be_nil
      end
    end

    context 'when only the IRQ line is seen by the poll' do
      context 'but interrupt disable is set' do
        subject(:interrupt_lines) do
          described_class.new(status:).tap { |lines| lines.assert_irq(described_class::MAPPER_IRQ, 8) }
        end

        let(:status) { Ruby::Nes::Cpu::Status.new.tap { |status| status.interrupt_disable = true } }

        it 'returns nothing' do
          expect(interrupt_lines.acknowledge(10)).to be_nil
        end
      end

      context 'and interrupt disable is clear' do
        subject(:interrupt_lines) do
          described_class.new(status:).tap { |lines| lines.assert_irq(described_class::MAPPER_IRQ, 8) }
        end

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'returns the IRQ vector' do
          expect(interrupt_lines.acknowledge(10)).to eq(0xFFFE)
        end

        it 'leaves the IRQ to take again' do
          interrupt_lines.acknowledge(10)
          expect(interrupt_lines.acknowledge(17)).to eq(0xFFFE)
        end
      end
    end

    context 'when the NMI edge is seen by the poll' do
      context 'and the IRQ line is not' do
        subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.nmi_line_changed(true, 8) } }

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'returns the NMI vector' do
          expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
        end

        it 'takes the NMI' do
          interrupt_lines.acknowledge(10)
          expect(interrupt_lines.acknowledge(17)).to be_nil
        end
      end

      context 'and the IRQ line is too' do
        subject(:interrupt_lines) do
          described_class.new(status:).tap do |lines|
            lines.nmi_line_changed(true, 8)
            lines.assert_irq(described_class::MAPPER_IRQ, 8)
          end
        end

        let(:status) { Ruby::Nes::Cpu::Status.new }

        it 'returns the NMI vector' do
          expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
        end

        it 'leaves the IRQ for the next poll' do
          interrupt_lines.acknowledge(10)
          expect(interrupt_lines.acknowledge(17)).to eq(0xFFFE)
        end
      end
    end
  end

  describe '#poll_with_interrupt_disable' do
    context 'when the I before the instruction was set and the status clears it (CLI)' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.assert_irq(described_class::MAPPER_IRQ, 4)
          lines.poll_with_interrupt_disable(true)
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'lets the next poll see I set' do
        expect(interrupt_lines.acknowledge(10)).to be_nil
      end

      it 'lets the poll after it see the status' do
        interrupt_lines.acknowledge(10)
        expect(interrupt_lines.acknowledge(12)).to eq(0xFFFE)
      end
    end

    context 'when the I before the instruction was clear and the status sets it (SEI)' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.assert_irq(described_class::MAPPER_IRQ, 4)
          lines.poll_with_interrupt_disable(false)
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new.tap { |status| status.interrupt_disable = true } }

      it 'lets the next poll see I clear' do
        expect(interrupt_lines.acknowledge(10)).to eq(0xFFFE)
      end

      it 'lets the poll after it see the status' do
        interrupt_lines.acknowledge(10)
        expect(interrupt_lines.acknowledge(17)).to be_nil
      end
    end
  end

  describe '#poll_one_cycle_early' do
    context 'when the NMI edge came two cycles before the step' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.nmi_line_changed(true, 8)
          lines.poll_one_cycle_early
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'keeps the next poll from seeing it' do
        expect(interrupt_lines.acknowledge(10)).to be_nil
      end

      it 'lets the poll after it see it' do
        interrupt_lines.acknowledge(10)
        expect(interrupt_lines.acknowledge(12)).to eq(0xFFFA)
      end
    end

    context 'when the IRQ line was asserted two cycles before the step' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.assert_irq(described_class::MAPPER_IRQ, 8)
          lines.poll_one_cycle_early
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'keeps the next poll from seeing it' do
        expect(interrupt_lines.acknowledge(10)).to be_nil
      end
    end

    context 'when the NMI edge came three cycles before the step' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.nmi_line_changed(true, 7)
          lines.poll_one_cycle_early
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'lets the next poll see it' do
        expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
      end
    end
  end

  # "The interrupt sequences themselves do not perform interrupt polling, meaning at least one instruction from the
  # interrupt handler will execute before another interrupt is serviced" (https://www.nesdev.org/wiki/CPU_interrupts).
  describe '#skip_next_poll' do
    context 'when an NMI edge came during the interrupt sequence' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.nmi_line_changed(true, 25)
          lines.skip_next_poll
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'keeps the next poll from seeing it' do
        expect(interrupt_lines.acknowledge(27)).to be_nil
      end

      it 'lets the poll after it see it' do
        interrupt_lines.acknowledge(27)
        expect(interrupt_lines.acknowledge(29)).to eq(0xFFFA)
      end
    end
  end

  # A DMA halts the CPU after it polled at the instruction's second-to-last cycle; it polls nothing while halted (plan
  # 22, decision 9). The instruction here ended on cycle 87 and the stall took 513 cycles, so the next step starts on
  # 600.
  describe '#poll_before_stall' do
    context "when the IRQ line fell before the instruction's poll cycle" do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.assert_irq(described_class::MAPPER_IRQ, 85)
          lines.poll_before_stall(513)
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'lets the next poll see it' do
        expect(interrupt_lines.acknowledge(600)).to eq(0xFFFE)
      end
    end

    context 'when the IRQ line fell during the stall' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.assert_irq(described_class::MAPPER_IRQ, 90)
          lines.poll_before_stall(513)
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'keeps the next poll from seeing it' do
        expect(interrupt_lines.acknowledge(600)).to be_nil
      end

      it 'lets the poll after it see it' do
        interrupt_lines.acknowledge(600)
        expect(interrupt_lines.acknowledge(602)).to eq(0xFFFE)
      end
    end
  end

  describe '#pending' do
    context 'when nothing is seen by the poll' do
      subject(:interrupt_lines) { described_class.new(status:) }

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'returns nothing' do
        expect(interrupt_lines.pending(10)).to be_nil
      end
    end

    context 'when the poll holds the I from before the instruction' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.assert_irq(described_class::MAPPER_IRQ, 4)
          lines.poll_with_interrupt_disable(true)
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'returns nothing' do
        expect(interrupt_lines.pending(10)).to be_nil
      end

      it 'leaves the held I to the acknowledge' do
        interrupt_lines.pending(10)
        expect(interrupt_lines.acknowledge(10)).to be_nil
      end
    end

    context 'when the poll comes one cycle early' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.nmi_line_changed(true, 8)
          lines.poll_one_cycle_early
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'leaves the early poll to the acknowledge' do
        interrupt_lines.pending(10)
        expect(interrupt_lines.acknowledge(10)).to be_nil
      end
    end

    context 'when the NMI edge is seen by the poll' do
      subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.nmi_line_changed(true, 8) } }

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'returns the NMI vector' do
        expect(interrupt_lines.pending(10)).to eq(0xFFFA)
      end

      it 'leaves the NMI to the acknowledge' do
        interrupt_lines.pending(10)
        expect(interrupt_lines.acknowledge(10)).to eq(0xFFFA)
      end
    end
  end

  describe '#hijacked_vector' do
    context 'when no NMI is pending' do
      subject(:interrupt_lines) { described_class.new(status:) }

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'returns the vector the sequence was taking' do
        expect(interrupt_lines.hijacked_vector(0xFFFE, 20)).to eq(0xFFFE)
      end
    end

    context 'when the NMI edge came after the fourth tick' do
      subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.nmi_line_changed(true, 24) } }

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'returns the vector the sequence was taking' do
        expect(interrupt_lines.hijacked_vector(0xFFFE, 20)).to eq(0xFFFE)
      end

      it 'leaves the NMI for the next poll' do
        interrupt_lines.hijacked_vector(0xFFFE, 20)
        expect(interrupt_lines.acknowledge(27)).to eq(0xFFFA)
      end
    end

    context 'when the NMI edge came by the fourth tick' do
      subject(:interrupt_lines) { described_class.new(status:).tap { |lines| lines.nmi_line_changed(true, 23) } }

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'returns the NMI vector' do
        expect(interrupt_lines.hijacked_vector(0xFFFE, 20)).to eq(0xFFFA)
      end

      it 'takes the NMI' do
        interrupt_lines.hijacked_vector(0xFFFE, 20)
        expect(interrupt_lines.acknowledge(27)).to be_nil
      end
    end
  end

  # Reset forgets an NMI not yet taken (plan 07, decision 6) and the poll's exceptions told by the instructions before
  # it; the lines keep the levels their devices set.
  describe '#reset' do
    context 'when an NMI and an IRQ are pending' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.nmi_line_changed(true, 0)
          lines.assert_irq(described_class::MAPPER_IRQ, 0)
          lines.reset
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'keeps only the IRQ' do
        expect(interrupt_lines.acknowledge(10)).to eq(0xFFFE)
      end
    end

    context 'when the poll holds the I from before an SEI' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.assert_irq(described_class::MAPPER_IRQ, 0)
          lines.poll_with_interrupt_disable(false)
          lines.reset
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new.tap { |status| status.interrupt_disable = true } }

      it 'lets the next poll see the status' do
        expect(interrupt_lines.acknowledge(10)).to be_nil
      end
    end

    context 'when a taken branch asked for an early poll' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.assert_irq(described_class::MAPPER_IRQ, 8)
          lines.poll_one_cycle_early
          lines.reset
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'lets the next poll look at the usual cycle' do
        expect(interrupt_lines.acknowledge(10)).to eq(0xFFFE)
      end
    end

    context 'when an interrupt sequence asked to skip the next poll' do
      subject(:interrupt_lines) do
        described_class.new(status:).tap do |lines|
          lines.assert_irq(described_class::MAPPER_IRQ, 0)
          lines.skip_next_poll
          lines.reset
        end
      end

      let(:status) { Ruby::Nes::Cpu::Status.new }

      it 'lets the next poll happen' do
        expect(interrupt_lines.acknowledge(10)).to eq(0xFFFE)
      end
    end
  end
end
