# frozen_string_literal: true

# The frame counter's interrupt flag (https://www.nesdev.org/wiki/APU_Frame_Counter, https://www.nesdev.org/wiki/APU):
# the 4-step sequence sets it "if interrupt inhibit flag (I bit) is clear", and it drives the CPU's IRQ line, as the
# FRAME_IRQ source, stamped with its cycle (plan 22, decision 6). It "can be acknowledged (cleared) by writing to $4017
# with interrupt inhibit flag set (I bit), or reading $4015 also clears the flag". The APU page adds "If an interrupt
# flag was set at the same moment of the read, it will read back as 1 but it will not be cleared", but apu_test's
# 6-irq_flag_timing, written against the console, needs a read on the cycle of the last set to clear it ("Flag last
# set too late", #5): the read clears it whenever it was set (plan 22, decision 7). Writing $00 or $80 to $4017 leaves
# it.
RSpec.describe Ruby::Nes::Apu::FrameInterrupt do
  describe '#trigger' do
    context 'when interrupts are inhibited' do
      subject(:frame_interrupt) { described_class.new(cpu:).tap { |interrupt| interrupt.change_inhibit(true, 5) } }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

      before { frame_interrupt.trigger(30) }

      it 'leaves the flag clear and asserts no IRQ', :aggregate_failures do
        expect(frame_interrupt).not_to be_flag
        expect(cpu).not_to have_received(:assert_irq)
      end
    end

    context 'when interrupts are not inhibited' do
      subject(:frame_interrupt) { described_class.new(cpu:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil) }

      before { frame_interrupt.trigger(30) }

      it 'sets the flag and asserts the IRQ on that cycle', :aggregate_failures do
        expect(frame_interrupt).to be_flag
        expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::FRAME_IRQ, 30)
      end
    end
  end

  describe '#read' do
    context 'when the flag is clear' do
      subject(:frame_interrupt) { described_class.new(cpu:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, release_irq: nil) }

      it 'returns false' do
        expect(frame_interrupt.read(40)).to be(false)
      end
    end

    context 'when the flag is set' do
      context 'and it was set on the cycle of the read' do
        subject(:frame_interrupt) { described_class.new(cpu:).tap { |interrupt| interrupt.trigger(40) } }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

        it 'returns true and clears the flag, releasing the IRQ on that cycle', :aggregate_failures do
          expect(frame_interrupt.read(40)).to be(true)
          expect(frame_interrupt).not_to be_flag
          expect(cpu).to have_received(:release_irq).with(Ruby::Nes::Cpu::InterruptLines::FRAME_IRQ, 40)
        end
      end

      context 'and it was set before the cycle of the read' do
        subject(:frame_interrupt) { described_class.new(cpu:).tap { |interrupt| interrupt.trigger(39) } }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

        it 'returns true and clears the flag, releasing the IRQ on that cycle', :aggregate_failures do
          expect(frame_interrupt.read(40)).to be(true)
          expect(frame_interrupt).not_to be_flag
          expect(cpu).to have_received(:release_irq).with(Ruby::Nes::Cpu::InterruptLines::FRAME_IRQ, 40)
        end
      end
    end
  end

  describe '#change_inhibit' do
    context 'when the flag is set' do
      context 'and the write clears the inhibit flag' do
        subject(:frame_interrupt) { described_class.new(cpu:).tap { |interrupt| interrupt.trigger(39) } }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

        before { frame_interrupt.change_inhibit(false, 50) }

        it 'keeps the flag' do
          expect(frame_interrupt).to be_flag
        end
      end

      context 'and the write sets the inhibit flag' do
        subject(:frame_interrupt) { described_class.new(cpu:).tap { |interrupt| interrupt.trigger(39) } }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

        before { frame_interrupt.change_inhibit(true, 50) }

        it 'clears the flag, releasing the IRQ on that cycle', :aggregate_failures do
          expect(frame_interrupt).not_to be_flag
          expect(cpu).to have_received(:release_irq).with(Ruby::Nes::Cpu::InterruptLines::FRAME_IRQ, 50)
        end
      end
    end
  end

  # "At power and reset, IRQ flag is clear" (apu_test's sibling suite apu_reset, irq_flag_cleared, plan 22 decision 4).
  describe '#reset' do
    context 'when the flag is set' do
      subject(:frame_interrupt) { described_class.new(cpu:).tap { |interrupt| interrupt.trigger(39) } }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

      before { frame_interrupt.reset(60) }

      it 'clears the flag, releasing the IRQ on that cycle', :aggregate_failures do
        expect(frame_interrupt).not_to be_flag
        expect(cpu).to have_received(:release_irq).with(Ruby::Nes::Cpu::InterruptLines::FRAME_IRQ, 60)
      end
    end
  end
end
