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

          before { counter.clock(120) }

          it 'asserts no IRQ' do
            expect(cpu).not_to have_received(:assert_irq)
          end
        end

        context 'and IRQs are enabled' do
          subject(:counter) { described_class.new(cpu:).tap(&:enable) }

          let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

          before { counter.clock(120) }

          it 'asserts the IRQ' do
            expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 120)
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
          counter.clock(120)
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
            irq_counter.clock(120)
          end
        end

        let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

        before { counter.clock(120) }

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
              irq_counter.clock(120)
            end
          end

          let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

          before { counter.clock(120) }

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
              irq_counter.clock(120)
            end
          end

          let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

          before { counter.clock(120) }

          it 'asserts the IRQ' do
            expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 120)
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
        2.times { irq_counter.clock(120) }
      end
    end

    let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

    it 'leaves the counter counting from its value' do
      counter.latch = 100
      counter.clock(120)
      expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 120)
    end
  end

  describe '#request_reload' do
    context 'when the latch is not 0' do
      # Loaded with 3 and decremented to 2, then cleared: the next clock loads 3 again, so the IRQ needs 3 more clocks.
      subject(:counter) do
        described_class.new(cpu:).tap do |irq_counter|
          irq_counter.latch = 3
          irq_counter.enable
          2.times { irq_counter.clock(120) }
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
        3.times { counter.clock(120) }
        expect(cpu).not_to have_received(:assert_irq)
        counter.clock(120)
        expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 120)
      end
    end

    context 'when the latch is 0' do
      # 2-details: "IRQ should be set when non-zero and reloading to 0 after clear".
      subject(:counter) do
        described_class.new(cpu:).tap do |irq_counter|
          irq_counter.latch = 3
          irq_counter.enable
          2.times { irq_counter.clock(120) }
          irq_counter.latch = 0
        end
      end

      let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

      it 'makes the next clock assert the IRQ' do
        counter.request_reload
        counter.clock(120)
        expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 120)
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

    # $E000 is written on the instruction's last cycle, its access cycle.
    let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil, access_cycle: 41) }

    it 'releases the IRQ on the access cycle' do
      counter.disable
      expect(cpu).to have_received(:release_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 41)
    end

    # 2-details: "Counter should run even when IRQ is disabled": five clocks while disabled (2, 1, 0, 2, 1), then the
    # first clock once enabled reaches 0.
    it 'keeps the counter running', :aggregate_failures do
      counter.disable
      5.times { counter.clock(120) }
      counter.enable
      expect(cpu).not_to have_received(:assert_irq)
      counter.clock(120)
      expect(cpu).to have_received(:assert_irq).with(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 120)
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

  # The PPU standing on M2 cycle `cycle`, the first clock can come on it, and each further one at least 3 M2 cycles
  # after the previous: A12 must stay low for "three falling edges of M2" before a rise counts (plan 28, decision 3).
  describe '#earliest_irq_cycle' do
    context 'when IRQs are disabled' do
      subject(:counter) { described_class.new(cpu:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

      it 'answers never' do
        expect(counter.earliest_irq_cycle(100)).to eq(Ruby::Nes::Mappers::Base::NEVER)
      end
    end

    context 'when IRQs are enabled' do
      context 'and the counter is 0' do
        context 'and the latch is 0' do
          subject(:counter) { described_class.new(cpu:).tap(&:enable) }

          let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

          it 'answers the cycle given, the next clock reloading 0' do
            expect(counter.earliest_irq_cycle(100)).to eq(100)
          end
        end

        context 'but the latch is not 0' do
          # Loading 4 takes a clock, then 4 more reach 0: 5 clocks, the last 12 M2 cycles after the first.
          subject(:counter) do
            described_class.new(cpu:).tap do |irq_counter|
              irq_counter.latch = 4
              irq_counter.enable
            end
          end

          let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

          it 'answers the cycle of the clock after the latch is counted down' do
            expect(counter.earliest_irq_cycle(100)).to eq(112)
          end
        end
      end

      context 'and the counter is above 0' do
        context 'and it is 1' do
          # Loaded with 2 and decremented to 1.
          subject(:counter) do
            described_class.new(cpu:).tap do |irq_counter|
              irq_counter.latch = 2
              irq_counter.enable
              2.times { irq_counter.clock(90) }
            end
          end

          let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

          it 'answers the cycle given' do
            expect(counter.earliest_irq_cycle(100)).to eq(100)
          end
        end

        context 'and it is above 1' do
          # Loaded with 3: 3 clocks reach 0, the last 6 M2 cycles after the first.
          subject(:counter) do
            described_class.new(cpu:).tap do |irq_counter|
              irq_counter.latch = 3
              irq_counter.enable
              irq_counter.clock(90)
            end
          end

          let(:cpu) { instance_double(Ruby::Nes::Cpu, assert_irq: nil, release_irq: nil) }

          it 'answers the cycle of the clock that reaches 0' do
            expect(counter.earliest_irq_cycle(100)).to eq(106)
          end
        end
      end
    end
  end
end
