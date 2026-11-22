# frozen_string_literal: true

# An APU interrupt flag: the frame counter's (https://www.nesdev.org/wiki/APU_Frame_Counter) and the DMC's
# (https://www.nesdev.org/wiki/APU_DMC). Each drives the CPU's IRQ line as its own source, FRAME_IRQ or DMC_IRQ, every
# change stamped with its cycle (plan 22, decision 6). The frame counter's 4-step sequence sets it "if interrupt
# inhibit flag (I bit) is clear", and the DMC's sample end if its IRQ enable flag is set: inhibited is not enabled.
# Inhibiting clears it: the frame flag "can be acknowledged (cleared) by writing to $4017 with interrupt inhibit flag
# set (I bit)", the DMC's by "clearing the sample-end interrupt flag (I bit) in $4010"; writing $00 or $80 to $4017
# leaves it. "Reading $4015 also clears the flag" of the frame counter "(but not the DMC interrupt flag)"
# (https://www.nesdev.org/wiki/APU), which a $4015 write clears instead, as reset clears both. The APU page adds "If an
# interrupt flag was set at the same moment of the read, it will read back as 1 but it will not be cleared", but
# apu_test's 6-irq_flag_timing, written against the console, needs a read on the cycle of the last set to clear it
# ("Flag last set too late", #5): the read clears it whenever it was set (plan 22, decision 7).
RSpec.describe Ruby::Nes::Apu::InterruptFlag do
  describe '#trigger' do
    context 'when interrupts are inhibited' do
      subject(:interrupt_flag) do
        described_class.new(source: Ruby::Nes::Cpu::InterruptLines::DMC_IRQ, cpu:).tap do |interrupt|
          interrupt.change_inhibit(true, 5)
        end
      end

      let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

      before { interrupt_flag.trigger(30) }

      it 'leaves the flag clear and asserts no IRQ', :aggregate_failures do
        expect(interrupt_flag).not_to be_flag
        expect(cpu).not_to have_received(:assert_irq)
      end
    end

    context 'when interrupts are not inhibited' do
      subject(:interrupt_flag) { described_class.new(source: Ruby::Nes::Cpu::InterruptLines::DMC_IRQ, cpu:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil) }

      before { interrupt_flag.trigger(30) }

      it 'sets the flag and asserts the IRQ on that cycle', :aggregate_failures do
        expect(interrupt_flag).to be_flag
        expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::DMC_IRQ, 30)
      end
    end
  end

  describe '#read' do
    context 'when the flag is clear' do
      subject(:interrupt_flag) { described_class.new(source: Ruby::Nes::Cpu::InterruptLines::FRAME_IRQ, cpu:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, release_irq: nil) }

      it 'returns false' do
        expect(interrupt_flag.read(40)).to be(false)
      end
    end

    context 'when the flag is set' do
      context 'and it was set on the cycle of the read' do
        subject(:interrupt_flag) do
          described_class.new(source: Ruby::Nes::Cpu::InterruptLines::FRAME_IRQ, cpu:).tap do |interrupt|
            interrupt.trigger(40)
          end
        end

        let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

        it 'returns true and clears the flag, releasing the IRQ on that cycle', :aggregate_failures do
          expect(interrupt_flag.read(40)).to be(true)
          expect(interrupt_flag).not_to be_flag
          expect(cpu).to have_received(:release_irq).with(Ruby::Nes::Cpu::InterruptLines::FRAME_IRQ, 40)
        end
      end

      context 'and it was set before the cycle of the read' do
        subject(:interrupt_flag) do
          described_class.new(source: Ruby::Nes::Cpu::InterruptLines::FRAME_IRQ, cpu:).tap do |interrupt|
            interrupt.trigger(39)
          end
        end

        let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

        it 'returns true and clears the flag, releasing the IRQ on that cycle', :aggregate_failures do
          expect(interrupt_flag.read(40)).to be(true)
          expect(interrupt_flag).not_to be_flag
          expect(cpu).to have_received(:release_irq).with(Ruby::Nes::Cpu::InterruptLines::FRAME_IRQ, 40)
        end
      end
    end
  end

  describe '#change_inhibit' do
    context 'when the flag is set' do
      context 'and the write clears the inhibit flag' do
        subject(:interrupt_flag) do
          described_class.new(source: Ruby::Nes::Cpu::InterruptLines::DMC_IRQ, cpu:).tap do |interrupt|
            interrupt.trigger(39)
          end
        end

        let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

        before { interrupt_flag.change_inhibit(false, 50) }

        it 'keeps the flag' do
          expect(interrupt_flag).to be_flag
        end
      end

      context 'and the write sets the inhibit flag' do
        subject(:interrupt_flag) do
          described_class.new(source: Ruby::Nes::Cpu::InterruptLines::DMC_IRQ, cpu:).tap do |interrupt|
            interrupt.trigger(39)
          end
        end

        let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

        before { interrupt_flag.change_inhibit(true, 50) }

        it 'clears the flag, releasing the IRQ on that cycle', :aggregate_failures do
          expect(interrupt_flag).not_to be_flag
          expect(cpu).to have_received(:release_irq).with(Ruby::Nes::Cpu::InterruptLines::DMC_IRQ, 50)
        end
      end
    end
  end

  # A $4015 write clears the DMC's flag; "At power and reset, IRQ flag is clear" (apu_reset's readme, plan 22 decision
  # 4).
  describe '#clear' do
    context 'when the flag is set' do
      subject(:interrupt_flag) do
        described_class.new(source: Ruby::Nes::Cpu::InterruptLines::DMC_IRQ, cpu:).tap do |interrupt|
          interrupt.trigger(39)
        end
      end

      let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

      it 'clears the flag, releasing the IRQ on that cycle', :aggregate_failures do
        interrupt_flag.clear(60)

        expect(interrupt_flag).not_to be_flag
        expect(cpu).to have_received(:release_irq).with(Ruby::Nes::Cpu::InterruptLines::DMC_IRQ, 60)
      end
    end
  end
end
