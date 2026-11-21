# frozen_string_literal: true

# MMC3's scanline counter (https://www.nesdev.org/wiki/MMC3#IRQ_Specifics), the "new" behaviour of the Sharp MMC3B/C
# (plan 21, decision 3). On a clock: if the counter is 0 or a reload was requested ($C001), it loads the latch ($C000),
# otherwise it decrements; if it is 0 afterwards and IRQs are enabled ($E001), the IRQ is asserted. "Writing any value
# to this register clears the MMC3 IRQ counter immediately" ($C001), and the readme of mmc3_test_2 adds that "the IRQ
# flag is not set when $C001 clears the counter"; $C000 "does not immediately affect the value within the counter";
# $E000 "will disable MMC3 interrupts AND acknowledge any pending interrupts", and "the counter will continue to run".
# With the latch at 0 the new behaviour asserts the IRQ on every clock (5-MMC3: "Should reload and set IRQ every clock
# when reload is 0"). Clearing the counter is all a reload request needs: a counter at 0 loads the latch on the next
# clock. It starts at 0, the latch at 0 and IRQs disabled (every register 0, plan 19 decision 6).
RSpec.describe Ruby::Nes::Mappers::Mmc3::IrqCounter do
  describe '#clock' do
    context 'when the counter is 0' do
      context 'and the latch is 0' do
        context 'but IRQs are disabled' do
          subject(:counter) { described_class.new(cpu:) }

          let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

          before { counter.clock }

          it 'asserts no IRQ' do
            expect(cpu).not_to have_received(:assert_irq)
          end
        end

        context 'and IRQs are enabled' do
          subject(:counter) { described_class.new(cpu:).tap(&:enable) }

          let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

          before { counter.clock }

          it 'asserts the IRQ' do
            expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ)
          end
        end
      end

      context 'and the latch is not 0' do
        subject(:counter) do
          described_class.new(cpu:).tap do |irq_counter|
            irq_counter.latch = 2
            irq_counter.enable
          end
        end

        let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

        it 'asserts no IRQ' do
          counter.clock
          expect(cpu).not_to have_received(:assert_irq)
        end
      end
    end

    context 'when the counter is above 0' do
      context 'and it stays above 0' do
        # Loaded with 3: the next clock takes it to 2.
        subject(:counter) do
          described_class.new(cpu:).tap do |irq_counter|
            irq_counter.latch = 3
            irq_counter.enable
            irq_counter.clock
          end
        end

        let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

        before { counter.clock }

        it 'asserts no IRQ' do
          expect(cpu).not_to have_received(:assert_irq)
        end
      end

      context 'and it decrements to 0' do
        context 'but IRQs are disabled' do
          # 1-clocking: "IRQ should never be set when disabled".
          subject(:counter) do
            described_class.new(cpu:).tap do |irq_counter|
              irq_counter.latch = 1
              irq_counter.clock
            end
          end

          let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

          before { counter.clock }

          it 'asserts no IRQ' do
            expect(cpu).not_to have_received(:assert_irq)
          end
        end

        context 'and IRQs are enabled' do
          # 1-clocking: "IRQ should be set when counter is decremented to 0".
          subject(:counter) do
            described_class.new(cpu:).tap do |irq_counter|
              irq_counter.latch = 1
              irq_counter.enable
              irq_counter.clock
            end
          end

          let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

          before { counter.clock }

          it 'asserts the IRQ' do
            expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ)
          end
        end
      end
    end
  end

  describe '#latch=' do
    # 1-clocking: "Writing to $C000 shouldn't cause reload". Loaded with 2 and decremented to 1, the latch becomes 100:
    # the next clock still reaches 0.
    subject(:counter) do
      described_class.new(cpu:).tap do |irq_counter|
        irq_counter.latch = 2
        irq_counter.enable
        2.times { irq_counter.clock }
      end
    end

    let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

    it 'leaves the counter counting from its value' do
      counter.latch = 100
      counter.clock
      expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ)
    end
  end

  describe '#request_reload' do
    context 'when the latch is not 0' do
      # Loaded with 3 and decremented to 2, then cleared: the next clock loads 3 again, so the IRQ needs 3 more clocks.
      subject(:counter) do
        described_class.new(cpu:).tap do |irq_counter|
          irq_counter.latch = 3
          irq_counter.enable
          2.times { irq_counter.clock }
        end
      end

      let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

      # 2-details: "IRQ should not be set when counter is cleared via $C001".
      it 'asserts no IRQ' do
        counter.request_reload
        expect(cpu).not_to have_received(:assert_irq)
      end

      # 1-clocking: "Should reload (no decrement) on first clock after clear".
      it 'makes the next clock load the latch instead of decrementing', :aggregate_failures do
        counter.request_reload
        3.times { counter.clock }
        expect(cpu).not_to have_received(:assert_irq)
        counter.clock
        expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ)
      end
    end

    context 'when the latch is 0' do
      # 2-details: "IRQ should be set when non-zero and reloading to 0 after clear".
      subject(:counter) do
        described_class.new(cpu:).tap do |irq_counter|
          irq_counter.latch = 3
          irq_counter.enable
          2.times { irq_counter.clock }
          irq_counter.latch = 0
        end
      end

      let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

      it 'makes the next clock assert the IRQ' do
        counter.request_reload
        counter.clock
        expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ)
      end
    end
  end

  describe '#disable' do
    subject(:counter) do
      described_class.new(cpu:).tap do |irq_counter|
        irq_counter.latch = 2
        irq_counter.enable
      end
    end

    let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

    it 'releases the IRQ' do
      counter.disable
      expect(cpu).to have_received(:release_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ)
    end

    # 2-details: "Counter should run even when IRQ is disabled": five clocks while disabled (2, 1, 0, 2, 1), then the
    # first clock once enabled reaches 0.
    it 'keeps the counter running', :aggregate_failures do
      counter.disable
      5.times { counter.clock }
      counter.enable
      expect(cpu).not_to have_received(:assert_irq)
      counter.clock
      expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ)
    end
  end

  describe '#enable' do
    subject(:counter) { described_class.new(cpu:) }

    let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

    before { counter.enable }

    it 'asserts nothing at once' do
      expect(cpu).not_to have_received(:assert_irq)
    end
  end
end
