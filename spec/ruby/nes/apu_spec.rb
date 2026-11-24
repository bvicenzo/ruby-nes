# frozen_string_literal: true

# The APU's registers (https://www.nesdev.org/wiki/APU), in CpuBus's `apu_registers:` slot: $4000-$4003 pulse 1,
# $4004-$4007 pulse 2, $4008-$400B triangle, $400C-$400F noise, $4015 status and enable, $4017 frame counter (writes;
# reads of $4017 are the controller port's). Reading $4015 gives `IF-D NT21`: the frame interrupt flag in bit 6 and the
# length counters above 0 of pulse 1, pulse 2, the triangle and the noise in bits 0-3 (the DMC bits come with plan 23);
# bit 5 "comes from the last cycle that did not read $4015", the data bus, and the read "does not affect open bus" (the
# bus leaves it, plan 22 decision 2). The other registers drive nothing. Writing $4015 enables or disables each channel
# by its bit. Of the triangle and the noise, plan 22 brings the length counters only (decision 8).
#
# The APU is caught up like the PPU (plan 22, decision 3): one CPU cycle at a time, the frame counter every cycle and
# the pulse timers every other one ("every second CPU cycles", on the even GET cycles, decision 5), after each step and,
# before a register access, through the access cycle (Cpu#access_cycle).
RSpec.describe Ruby::Nes::Apu do
  describe '#cpu_read' do
    context 'when the address is not $4015' do
      subject(:apu) { described_class.new(cpu:, frame_counter:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }

      it 'leaves the data bus' do
        expect(apu.cpu_read(0x4000, 0x5A)).to eq(0x5A)
      end
    end

    context 'when the address is $4015' do
      context 'and nothing sounds nor interrupts' do
        context 'and the data bus has bit 5 clear' do
          subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

          let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
          let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
          let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil, quiet_ticks: 0) }
          let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil, quiet_ticks: 0) }

          it 'returns $00' do
            expect(apu.cpu_read(0x4015, 0xDF)).to eq(0x00)
          end
        end

        context 'and the data bus has bit 5 set' do
          subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

          let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
          let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
          let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil, quiet_ticks: 0) }
          let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil, quiet_ticks: 0) }

          it 'returns bit 5 from the data bus' do
            expect(apu.cpu_read(0x4015, 0x20)).to eq(0x20)
          end
        end
      end

      context 'and pulse 1 sounds' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: true, tick_timer: nil, quiet_ticks: 0) }
        let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil, quiet_ticks: 0) }

        it 'sets bit 0' do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x01)
        end
      end

      context 'and pulse 2 sounds' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil, quiet_ticks: 0) }
        let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: true, tick_timer: nil, quiet_ticks: 0) }

        it 'sets bit 1' do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x02)
        end
      end

      context 'and the triangle sounds' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, triangle:, noise:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, quiet_ticks: 0, active?: true) }
        let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, quiet_ticks: 0, active?: false) }

        it 'sets bit 2' do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x04)
        end
      end

      context 'and the noise sounds' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, triangle:, noise:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, quiet_ticks: 0, active?: false) }
        let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, quiet_ticks: 0, active?: true) }

        it 'sets bit 3' do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x08)
        end
      end

      context 'and the DMC has bytes remaining' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, dmc:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, active?: true, interrupt?: false, tick_timer: nil, quiet_ticks: 0) }

        it 'sets bit 4' do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x10)
        end
      end

      context 'and the DMC interrupt flag is set' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, dmc:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, active?: false, interrupt?: true, tick_timer: nil, quiet_ticks: 0) }

        it 'sets bit 7, leaving the flag set', :aggregate_failures do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x80)
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x80)
        end
      end

      context 'and the frame interrupt flag reads set' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: true, :cpu= => nil) }
        let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil, quiet_ticks: 0) }
        let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil, quiet_ticks: 0) }

        it 'sets bit 6, reading the flag on the access cycle', :aggregate_failures do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x40)
          expect(frame_interrupt).to have_received(:read).with(9)
        end
      end

      context 'and the APU is behind the CPU' do
        context 'and no DMA halts the CPU meanwhile' do
          subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

          let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
          let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
          let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil, quiet_ticks: 0) }
          let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil, quiet_ticks: 0) }

          it 'catches it up through the access cycle first', :aggregate_failures do
            apu.cpu_read(0x4015, 0x00)
            expect(frame_counter).to have_received(:tick).exactly(10).times
            expect(frame_counter).to have_received(:tick).with(9)
          end
        end

        # "DMA can only halt on CPU read cycles" (https://www.nesdev.org/wiki/DMA): the read comes after the stall.
        context 'but the DMC halts the CPU while it catches up' do
          subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, dmc:) }

          let(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, cycles: 10) }
          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
          let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
          let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, active?: false, interrupt?: false, quiet_ticks: 0) }

          before do
            allow(dmc).to receive(:tick_timer)
            allow(dmc).to receive(:tick_timer).with(4) { cpu.halt(4) }
            apu.cpu_read(0x4015, 0x00)
          end

          it 'catches it up through the stall, then reads on the access cycle after it', :aggregate_failures do
            expect(frame_counter).to have_received(:tick).exactly(14).times
            expect(frame_interrupt).to have_received(:read).with(13)
          end
        end
      end
    end
  end

  describe '#cpu_write' do
    context 'when the address is a pulse 1 register' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, first_pulse:, second_pulse:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil, quiet_ticks: 0) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil, quiet_ticks: 0) }

      before { apu.cpu_write(0x4003, 0xF8) }

      it 'writes that register of pulse 1', :aggregate_failures do
        expect(first_pulse).to have_received(:write).with(3, 0xF8)
        expect(second_pulse).not_to have_received(:write)
      end
    end

    context 'when the address is a pulse 2 register' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, first_pulse:, second_pulse:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil, quiet_ticks: 0) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil, quiet_ticks: 0) }

      before { apu.cpu_write(0x4004, 0xBF) }

      it 'writes that register of pulse 2', :aggregate_failures do
        expect(second_pulse).to have_received(:write).with(0, 0xBF)
        expect(first_pulse).not_to have_received(:write)
      end
    end

    context 'when the address is a triangle register' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, triangle:, noise:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, quiet_ticks: 0, write: nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, quiet_ticks: 0, write: nil) }

      before { apu.cpu_write(0x400B, 0xF8) }

      it 'writes that register of the triangle', :aggregate_failures do
        expect(triangle).to have_received(:write).with(3, 0xF8)
        expect(noise).not_to have_received(:write)
      end
    end

    context 'when the address is a noise register' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, triangle:, noise:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, quiet_ticks: 0, write: nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, quiet_ticks: 0, write: nil) }

      before { apu.cpu_write(0x400C, 0x30) }

      it 'writes that register of the noise', :aggregate_failures do
        expect(noise).to have_received(:write).with(0, 0x30)
        expect(triangle).not_to have_received(:write)
      end
    end

    context 'when the address is a DMC register' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, noise:, dmc:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, quiet_ticks: 0, write: nil) }
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, write: nil, tick_timer: nil, quiet_ticks: 0) }

      before { apu.cpu_write(0x4013, 0x01) }

      it 'writes that register of the DMC', :aggregate_failures do
        expect(dmc).to have_received(:write).with(3, 0x01)
        expect(noise).not_to have_received(:write)
      end
    end

    context 'when the address is $4015' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, :enabled= => nil, tick_timer: nil, quiet_ticks: 0) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, :enabled= => nil, tick_timer: nil, quiet_ticks: 0) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, quiet_ticks: 0, :enabled= => nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, quiet_ticks: 0, :enabled= => nil) }

      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, write_status: nil, tick_timer: nil, quiet_ticks: 0) }

      before { apu.cpu_write(0x4015, 0x1A) }

      it 'enables or disables each channel by its bit, the DMC on the access cycle', :aggregate_failures do
        expect(first_pulse).to have_received(:enabled=).with(false)
        expect(second_pulse).to have_received(:enabled=).with(true)
        expect(triangle).to have_received(:enabled=).with(false)
        expect(noise).to have_received(:enabled=).with(true)
        expect(dmc).to have_received(:write_status).with(true, 9)
      end
    end

    context 'when the address is $4017' do
      subject(:apu) { described_class.new(cpu:, frame_counter:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0, write: nil) }

      before { apu.cpu_write(0x4017, 0x40) }

      it 'writes the frame counter on the access cycle' do
        expect(frame_counter).to have_received(:write).with(0x40, 9)
      end
    end

    # OAMDMA: the bus starts OAM DMA instead (plan 11, decision 2).
    context 'when the address is $4014' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, first_pulse:, second_pulse:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0, write: nil) }
      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil, quiet_ticks: 0) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil, quiet_ticks: 0) }

      before { apu.cpu_write(0x4014, 0x02) }

      it 'writes nothing', :aggregate_failures do
        expect(first_pulse).not_to have_received(:write)
        expect(second_pulse).not_to have_received(:write)
        expect(frame_counter).not_to have_received(:write)
      end
    end

    context 'when the APU is behind the CPU' do
      context 'and no DMA halts the CPU meanwhile' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, first_pulse:, second_pulse:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
        let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil, quiet_ticks: 0) }
        let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, tick_timer: nil, quiet_ticks: 0) }

        before { apu.cpu_write(0x4000, 0x30) }

        it 'catches it up through the access cycle first', :aggregate_failures do
          expect(frame_counter).to have_received(:tick).exactly(10).times
          expect(frame_counter).to have_received(:tick).with(9)
        end
      end

      # The hardware would delay the halt past the write ("DMA can only halt on CPU read cycles",
      # https://www.nesdev.org/wiki/DMA); the APU lands the write after it so its stamp and its state agree (Known gaps:
      # DMC DMA timing).
      context 'but the DMC halts the CPU while it catches up' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, dmc:) }

        let(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, cycles: 10) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0, write: nil) }
        let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, quiet_ticks: 0) }

        before do
          allow(dmc).to receive(:tick_timer)
          allow(dmc).to receive(:tick_timer).with(4) { cpu.halt(4) }
          apu.cpu_write(0x4017, 0x40)
        end

        it 'catches it up through the stall, then writes on the access cycle after it', :aggregate_failures do
          expect(frame_counter).to have_received(:tick).exactly(14).times
          expect(frame_counter).to have_received(:write).with(0x40, 13)
        end
      end
    end
  end

  # Runs every CPU cycle before the target (plan 22, decision 3) by runs (plan 29) that only the slow units bound since
  # plan 33: the frame counter, the pulses and the DMC. The cycles before the first one on which one of them changes are
  # quiet: they skip them at once, the pulses and the DMC by the get cycles among them, and the triangle and the noise,
  # which can change every cycle or every 4, go through them clock by clock (FastChannels), handed the slow channels'
  # outputs when a resampler takes the mix. The cycle with a slow change runs as before: the frame counter and the
  # triangle every cycle, the other timers on even ones, and the cycle's mix handed on its own. Without a resampler,
  # nothing is mixed (plan 24, decision 6). The doubles answer NEVER for the units that do not bound the run.
  describe '#catch_up' do
    context 'when the APU has already reached the target' do
      subject(:apu) { described_class.new(frame_counter:) }

      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter) }

      it 'runs nothing' do
        expect { apu.catch_up(0) }.not_to raise_error
      end
    end

    context 'when it is behind the target' do
      context "and a slow unit changes on the APU's next cycle" do
        context 'and no resampler is attached' do
          subject(:apu) { described_class.new(frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:) }

          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, quiet_cycles: 0, tick: nil) }
          let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: 0, tick_timer: nil, output: 3) }
          let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: 0, tick_timer: nil, output: 4) }
          let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, output: 5) }
          let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, output: 6) }
          let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, quiet_ticks: 0, tick_timer: nil, output: 7) }

          before { apu.catch_up(5) }

          it(
            'ticks the frame counter and the triangle every cycle, the other timers on even ones',
            :aggregate_failures
          ) do
            expect(frame_counter).to have_received(:tick).with(0).ordered
            expect(frame_counter).to have_received(:tick).with(4).ordered
            expect(frame_counter).to have_received(:tick).exactly(5).times
            expect(triangle).to have_received(:tick_timer).exactly(5).times
            expect(first_pulse).to have_received(:tick_timer).exactly(3).times
            expect(second_pulse).to have_received(:tick_timer).exactly(3).times
            expect(noise).to have_received(:tick_timer).exactly(3).times
            expect(dmc).to have_received(:tick_timer).exactly(3).times
            expect(dmc).to have_received(:tick_timer).with(0)
            expect(dmc).to have_received(:tick_timer).with(2)
            expect(dmc).to have_received(:tick_timer).with(4)
          end

          it 'never asks the channels for their output', :aggregate_failures do
            expect(first_pulse).not_to have_received(:output)
            expect(second_pulse).not_to have_received(:output)
            expect(triangle).not_to have_received(:output)
            expect(noise).not_to have_received(:output)
            expect(dmc).not_to have_received(:output)
          end
        end

        context 'and a resampler is attached' do
          subject(:apu) do
            described_class.new(frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:, resampler:)
          end

          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, quiet_cycles: 0, tick: nil) }
          let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: 0, tick_timer: nil, output: 3) }
          let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: 0, tick_timer: nil, output: 4) }
          let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, output: 5) }
          let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, output: 6) }
          let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, quiet_ticks: 0, tick_timer: nil, output: 7) }
          let(:resampler) { instance_double(Ruby::Nes::Audio::Resampler, add: nil) }

          before { apu.catch_up(1) }

          it "hands it that cycle's mix as one level" do
            expect(resampler).to have_received(:add).once.with(Ruby::Nes::Apu::Mixer.mix(3, 4, 5, 6, 7))
          end
        end
      end

      context 'and the first slow change comes later' do
        context 'and the frame counter bounds the run' do
          subject(:apu) do
            described_class.new(frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:, fast_channels:)
          end

          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, skip: nil, tick: nil) }
          let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }
          let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }
          let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil) }
          let(:noise) { instance_double(Ruby::Nes::Apu::Noise) }
          let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }
          let(:fast_channels) { instance_double(Ruby::Nes::Apu::FastChannels, run: nil) }

          before do
            allow(frame_counter).to receive(:quiet_cycles).and_return(3, 0)
            apu.catch_up(4)
          end

          it 'runs the quiet cycles before it at once, then its cycle', :aggregate_failures do
            expect(frame_counter).to have_received(:skip).once.with(3).ordered
            expect(fast_channels).to have_received(:run).once.with(0, 3).ordered
            expect(frame_counter).to have_received(:tick).once.with(3).ordered
            expect(triangle).to have_received(:tick_timer).once
            expect(first_pulse).to have_received(:skip).once.with(2)
          end
        end

        context 'and a pulse bounds the run' do
          context 'and the run starts on a get cycle' do
            subject(:apu) do
              described_class.new(frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:, fast_channels:)
            end

            let(:frame_counter) do
              instance_double(Ruby::Nes::Apu::FrameCounter, quiet_cycles: Ruby::Nes::Apu::NEVER, skip: nil, tick: nil)
            end
            let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, skip: nil, tick_timer: nil) }
            let(:second_pulse) do
              instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, tick_timer: nil)
            end
            let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil) }
            let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil) }
            let(:dmc) do
              instance_double(Ruby::Nes::Apu::Dmc, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, tick_timer: nil)
            end
            let(:fast_channels) { instance_double(Ruby::Nes::Apu::FastChannels, run: nil) }

            before do
              allow(first_pulse).to receive(:quiet_ticks).and_return(2, 0)
              apu.catch_up(5)
            end

            it 'runs the cycles before its tick at once, then that cycle', :aggregate_failures do
              expect(frame_counter).to have_received(:skip).once.with(4).ordered
              expect(first_pulse).to have_received(:skip).once.with(2).ordered
              expect(fast_channels).to have_received(:run).once.with(0, 4).ordered
              expect(frame_counter).to have_received(:tick).once.with(4).ordered
              expect(first_pulse).to have_received(:tick_timer).once.ordered
              expect(dmc).to have_received(:tick_timer).once.with(4)
            end
          end

          context 'and the run starts on a put cycle' do
            subject(:apu) do
              described_class.new(frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:, fast_channels:)
            end

            let(:frame_counter) do
              instance_double(Ruby::Nes::Apu::FrameCounter, quiet_cycles: Ruby::Nes::Apu::NEVER, skip: nil, tick: nil)
            end
            let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, skip: nil, tick_timer: nil) }
            let(:second_pulse) do
              instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, tick_timer: nil)
            end
            let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil) }
            let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil) }
            let(:dmc) do
              instance_double(Ruby::Nes::Apu::Dmc, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, tick_timer: nil)
            end
            let(:fast_channels) { instance_double(Ruby::Nes::Apu::FastChannels, run: nil) }

            before do
              allow(first_pulse).to receive(:quiet_ticks).and_return(2, 2, 0)
              apu.catch_up(1)
              apu.catch_up(7)
            end

            it 'runs the cycles before its tick at once, then that cycle', :aggregate_failures do
              expect(frame_counter).to have_received(:skip).once.with(5).ordered
              expect(fast_channels).to have_received(:run).once.with(1, 5).ordered
              expect(frame_counter).to have_received(:tick).once.with(6).ordered
              expect(first_pulse).to have_received(:skip).once.with(2)
            end
          end
        end

        context 'and the DMC bounds the run' do
          context 'and the run starts on a get cycle' do
            subject(:apu) do
              described_class.new(frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:, fast_channels:)
            end

            let(:frame_counter) do
              instance_double(Ruby::Nes::Apu::FrameCounter, quiet_cycles: Ruby::Nes::Apu::NEVER, skip: nil, tick: nil)
            end
            let(:first_pulse) do
              instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, tick_timer: nil)
            end
            let(:second_pulse) do
              instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, tick_timer: nil)
            end
            let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil) }
            let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil) }
            let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, skip: nil, tick_timer: nil) }
            let(:fast_channels) { instance_double(Ruby::Nes::Apu::FastChannels, run: nil) }

            before do
              allow(dmc).to receive(:quiet_ticks).and_return(2, 0)
              apu.catch_up(5)
            end

            it 'runs the cycles before its tick at once, then that cycle', :aggregate_failures do
              expect(frame_counter).to have_received(:skip).once.with(4).ordered
              expect(dmc).to have_received(:skip).once.with(2).ordered
              expect(fast_channels).to have_received(:run).once.with(0, 4).ordered
              expect(frame_counter).to have_received(:tick).once.with(4).ordered
              expect(dmc).to have_received(:tick_timer).once.with(4).ordered
            end
          end

          context 'and the run starts on a put cycle' do
            subject(:apu) do
              described_class.new(frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:, fast_channels:)
            end

            let(:frame_counter) do
              instance_double(Ruby::Nes::Apu::FrameCounter, quiet_cycles: Ruby::Nes::Apu::NEVER, skip: nil, tick: nil)
            end
            let(:first_pulse) do
              instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, tick_timer: nil)
            end
            let(:second_pulse) do
              instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, tick_timer: nil)
            end
            let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil) }
            let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil) }
            let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, skip: nil, tick_timer: nil) }
            let(:fast_channels) { instance_double(Ruby::Nes::Apu::FastChannels, run: nil) }

            before do
              allow(dmc).to receive(:quiet_ticks).and_return(2, 2, 0)
              apu.catch_up(1)
              apu.catch_up(7)
            end

            it 'runs the cycles before its tick at once, then that cycle', :aggregate_failures do
              expect(frame_counter).to have_received(:skip).once.with(5).ordered
              expect(fast_channels).to have_received(:run).once.with(1, 5).ordered
              expect(frame_counter).to have_received(:tick).once.with(6).ordered
              expect(dmc).to have_received(:tick_timer).once.with(6).ordered
            end
          end
        end

        # A triangle at period 0 clocks on every cycle (plan 33).
        context 'and the triangle would change before it' do
          subject(:apu) do
            described_class.new(frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:, fast_channels:)
          end

          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, skip: nil, tick: nil) }
          let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }
          let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }
          let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, quiet_ticks: 0, tick_timer: nil) }
          let(:noise) { instance_double(Ruby::Nes::Apu::Noise, quiet_ticks: Ruby::Nes::Apu::NEVER) }
          let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }
          let(:fast_channels) { instance_double(Ruby::Nes::Apu::FastChannels, run: nil) }

          before do
            allow(frame_counter).to receive(:quiet_cycles).and_return(3, 0)
            apu.catch_up(4)
          end

          it 'does not cut the run', :aggregate_failures do
            expect(fast_channels).to have_received(:run).once.with(0, 3)
            expect(triangle).to have_received(:tick_timer).once
          end
        end

        # A noise at its shortest period clocks every 4 cycles (plan 33).
        context 'and the noise would change before it' do
          subject(:apu) do
            described_class.new(frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:, fast_channels:)
          end

          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, skip: nil, tick: nil) }
          let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }
          let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }
          let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, quiet_ticks: Ruby::Nes::Apu::NEVER, tick_timer: nil) }
          let(:noise) { instance_double(Ruby::Nes::Apu::Noise, quiet_ticks: 0, tick_timer: nil) }
          let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }
          let(:fast_channels) { instance_double(Ruby::Nes::Apu::FastChannels, run: nil) }

          before do
            allow(frame_counter).to receive(:quiet_cycles).and_return(3, 0)
            apu.catch_up(4)
          end

          it 'does not cut the run', :aggregate_failures do
            expect(fast_channels).to have_received(:run).once.with(0, 3)
            expect(noise).not_to have_received(:tick_timer)
          end
        end
      end

      context 'and no slow unit changes before the target' do
        context 'and no resampler is attached' do
          subject(:apu) do
            described_class.new(frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:, fast_channels:)
          end

          let(:frame_counter) do
            instance_double(Ruby::Nes::Apu::FrameCounter, quiet_cycles: Ruby::Nes::Apu::NEVER, skip: nil)
          end
          let(:first_pulse) do
            instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 3)
          end
          let(:second_pulse) do
            instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 4)
          end
          let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle) }
          let(:noise) { instance_double(Ruby::Nes::Apu::Noise) }
          let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 7) }
          let(:fast_channels) { instance_double(Ruby::Nes::Apu::FastChannels, run: nil) }

          before { apu.catch_up(5) }

          it(
            'skips the slow units to the target at once, the pulses and the DMC by the get cycles among them',
            :aggregate_failures
          ) do
            expect(frame_counter).to have_received(:skip).once.with(5)
            expect(first_pulse).to have_received(:skip).once.with(3)
            expect(second_pulse).to have_received(:skip).once.with(3)
            expect(dmc).to have_received(:skip).once.with(3)
          end

          it 'runs the fast channels through it, without the outputs to mix', :aggregate_failures do
            expect(fast_channels).to have_received(:run).once.with(0, 5)
            expect(first_pulse).not_to have_received(:output)
            expect(second_pulse).not_to have_received(:output)
            expect(dmc).not_to have_received(:output)
          end
        end

        context 'and a resampler is attached' do
          subject(:apu) do
            described_class.new(
              frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:, resampler:, fast_channels:
            )
          end

          let(:frame_counter) do
            instance_double(Ruby::Nes::Apu::FrameCounter, quiet_cycles: Ruby::Nes::Apu::NEVER, skip: nil)
          end
          let(:first_pulse) do
            instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 3)
          end
          let(:second_pulse) do
            instance_double(Ruby::Nes::Apu::Pulse, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 4)
          end
          let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle) }
          let(:noise) { instance_double(Ruby::Nes::Apu::Noise) }
          let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 7) }
          let(:resampler) { instance_double(Ruby::Nes::Audio::Resampler) }
          let(:fast_channels) { instance_double(Ruby::Nes::Apu::FastChannels, run: nil) }

          before { apu.catch_up(5) }

          it "runs the fast channels through it with the slow channels' outputs" do
            expect(fast_channels).to have_received(:run).once.with(0, 5, 3, 4, 7)
          end
        end
      end
    end
  end

  # The console catches the APU up only from this cycle on (plan 29): one past the earlier of the frame counter's next
  # interrupt and the DMC's next fetch, asked from the APU's next cycle, since an event on cycle F changes the CPU only
  # after the step that crosses F. Kept until a catch-up, a register write or a reset.
  describe '#sync_cycle' do
    context 'when neither the frame counter nor the DMC can reach the CPU' do
      subject(:apu) { described_class.new(frame_counter:, dmc:) }

      let(:frame_counter) do
        instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0, next_interrupt_cycle: Ruby::Nes::Apu::NEVER)
      end
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, tick_timer: nil, quiet_ticks: 0, next_fetch_cycle: Ruby::Nes::Apu::NEVER) }

      it 'answers never' do
        expect(apu.sync_cycle).to eq(Ruby::Nes::Apu::NEVER)
      end
    end

    context "when the frame counter's next interrupt comes first" do
      subject(:apu) { described_class.new(frame_counter:, dmc:) }

      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0, next_interrupt_cycle: 500) }
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, tick_timer: nil, quiet_ticks: 0, next_fetch_cycle: 700) }

      before { apu.catch_up(10) }

      it 'answers the cycle after it, asked from the next cycle the APU runs', :aggregate_failures do
        expect(apu.sync_cycle).to eq(501)
        expect(frame_counter).to have_received(:next_interrupt_cycle).with(10)
        expect(dmc).to have_received(:next_fetch_cycle).with(10)
      end
    end

    context "when the DMC's next fetch comes first" do
      subject(:apu) { described_class.new(frame_counter:, dmc:) }

      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0, next_interrupt_cycle: 700) }
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, tick_timer: nil, quiet_ticks: 0, next_fetch_cycle: 500) }

      it 'answers the cycle after it' do
        expect(apu.sync_cycle).to eq(501)
      end
    end

    context 'when both come on the same cycle' do
      subject(:apu) { described_class.new(frame_counter:, dmc:) }

      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0, next_interrupt_cycle: 500) }
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, tick_timer: nil, quiet_ticks: 0, next_fetch_cycle: 500) }

      it 'answers the cycle after it' do
        expect(apu.sync_cycle).to eq(501)
      end
    end

    context 'when it was asked before' do
      context 'and nothing ran since' do
        subject(:apu) { described_class.new(frame_counter:, dmc:) }

        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
        let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, tick_timer: nil, quiet_ticks: 0, next_fetch_cycle: 700) }

        before do
          allow(frame_counter).to receive(:next_interrupt_cycle).and_return(500, 900)
          apu.sync_cycle
        end

        it 'keeps its answer without asking again', :aggregate_failures do
          expect(apu.sync_cycle).to eq(501)
          expect(frame_counter).to have_received(:next_interrupt_cycle).once
        end
      end

      context 'but the APU caught up since' do
        subject(:apu) { described_class.new(frame_counter:, dmc:) }

        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
        let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, tick_timer: nil, quiet_ticks: 0, next_fetch_cycle: 2000) }

        before do
          allow(frame_counter).to receive(:next_interrupt_cycle).and_return(500, 900)
          apu.sync_cycle
          apu.catch_up(10)
        end

        it 'answers anew' do
          expect(apu.sync_cycle).to eq(901)
        end
      end

      context 'but a register was written since' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, dmc:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 0, access_cycle: 0) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0) }
        let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, tick_timer: nil, quiet_ticks: 0, next_fetch_cycle: 2000) }

        before do
          allow(frame_counter).to receive(:next_interrupt_cycle).and_return(500, 900)
          apu.sync_cycle
          apu.cpu_write(0x4000, 0x3F)
        end

        it 'answers anew' do
          expect(apu.sync_cycle).to eq(901)
        end
      end

      context 'but the APU was reset since' do
        subject(:apu) { described_class.new(frame_counter:, frame_interrupt:, dmc:) }

        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0, reset: nil) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, clear: nil) }
        let(:dmc) do
          instance_double(
            Ruby::Nes::Apu::Dmc,
            tick_timer: nil,
            quiet_ticks: 0,
            write_status: nil,
            reset: nil,
            next_fetch_cycle: 2000
          )
        end

        before do
          allow(frame_counter).to receive(:next_interrupt_cycle).and_return(500, 900)
          apu.sync_cycle
          apu.reset
        end

        it 'answers anew' do
          expect(apu.sync_cycle).to eq(901)
        end
      end
    end
  end

  describe '#quarter_frame' do
    context 'when the frame counter clocks it' do
      subject(:apu) { described_class.new(first_pulse:, second_pulse:, triangle:, noise:) }

      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quarter_frame: nil) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, quarter_frame: nil) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, quarter_frame: nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, quarter_frame: nil) }

      it "clocks the pulses' and the noise's envelopes and the triangle's linear counter", :aggregate_failures do
        apu.quarter_frame
        expect(first_pulse).to have_received(:quarter_frame)
        expect(second_pulse).to have_received(:quarter_frame)
        expect(triangle).to have_received(:quarter_frame)
        expect(noise).to have_received(:quarter_frame)
      end
    end
  end

  describe '#half_frame' do
    context 'when the frame counter clocks it' do
      subject(:apu) { described_class.new(first_pulse:, second_pulse:, triangle:, noise:) }

      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, half_frame: nil) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, half_frame: nil) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, quiet_ticks: 0, half_frame: nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, quiet_ticks: 0, half_frame: nil) }

      it 'clocks the four channels', :aggregate_failures do
        apu.half_frame
        expect(first_pulse).to have_received(:half_frame)
        expect(second_pulse).to have_received(:half_frame)
        expect(triangle).to have_received(:half_frame)
        expect(noise).to have_received(:half_frame)
      end
    end
  end

  describe '#output' do
    context 'when the channels sound' do
      subject(:apu) { described_class.new(first_pulse:, second_pulse:, triangle:, noise:, dmc:) }

      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, output: 15) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, output: 3) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, output: 7) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, output: 2) }
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, output: 100) }

      it 'is their mix' do
        expect(apu.output).to eq(Ruby::Nes::Apu::Mixer.mix(15, 3, 7, 2, 100))
      end
    end
  end

  # The Console builds the CPU and the bus after the APU.
  describe '#cpu=' do
    context 'when the console wires the CPU' do
      subject(:apu) { described_class.new(frame_interrupt:, dmc:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu) }
      let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, :cpu= => nil) }
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, :cpu= => nil) }

      it 'gives it to the frame interrupt flag and the DMC', :aggregate_failures do
        apu.cpu = cpu
        expect(frame_interrupt).to have_received(:cpu=).with(cpu)
        expect(dmc).to have_received(:cpu=).with(cpu)
      end
    end
  end

  describe '#memory=' do
    context 'when the console wires the bus' do
      subject(:apu) { described_class.new(dmc:) }

      let(:memory) { FlatBus.new }
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, :memory= => nil) }

      it 'gives it to the DMC' do
        apu.memory = memory
        expect(dmc).to have_received(:memory=).with(memory)
      end
    end
  end

  # "At power and reset, $4015 is cleared", "IRQ flag is clear", and "last value written to $4017 is written again"
  # (apu_reset's readme; plan 22, decision 4); after reset the "Triangle phase" is 0 and "[$4011] &= 1"
  # (https://www.nesdev.org/wiki/CPU_power_up_state). The APU stands at the last cycle it caught up to.
  describe '#reset' do
    context 'when the console is reset' do
      subject(:apu) do
        described_class.new(frame_counter:, frame_interrupt:, first_pulse:, second_pulse:, triangle:, noise:, dmc:)
      end

      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, quiet_cycles: 0, reset: nil) }
      let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, clear: nil) }
      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, :enabled= => nil, tick_timer: nil, quiet_ticks: 0) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, :enabled= => nil, tick_timer: nil, quiet_ticks: 0) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, :enabled= => nil, tick_timer: nil, quiet_ticks: 0, reset: nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, :enabled= => nil, tick_timer: nil, quiet_ticks: 0) }
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, write_status: nil, tick_timer: nil, quiet_ticks: 0, reset: nil) }

      before do
        apu.catch_up(30)
        apu.reset
      end

      it 'disables the five channels, the DMC on its cycle', :aggregate_failures do
        expect(first_pulse).to have_received(:enabled=).with(false)
        expect(second_pulse).to have_received(:enabled=).with(false)
        expect(triangle).to have_received(:enabled=).with(false)
        expect(noise).to have_received(:enabled=).with(false)
        expect(dmc).to have_received(:write_status).with(false, 30)
      end

      it 'clears the frame interrupt flag and writes $4017 again, on its cycle', :aggregate_failures do
        expect(frame_interrupt).to have_received(:clear).with(30)
        expect(frame_counter).to have_received(:reset).with(30)
      end

      it "resets the triangle's phase and the DMC's level", :aggregate_failures do
        expect(triangle).to have_received(:reset)
        expect(dmc).to have_received(:reset)
      end
    end
  end
end
