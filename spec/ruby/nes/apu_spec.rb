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
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }

      it 'leaves the data bus' do
        expect(apu.cpu_read(0x4000, 0x5A)).to eq(0x5A)
      end
    end

    context 'when the address is $4015' do
      context 'and nothing sounds nor interrupts' do
        context 'and the data bus has bit 5 clear' do
          subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

          let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
          let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
          let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil) }
          let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil) }

          it 'returns $00' do
            expect(apu.cpu_read(0x4015, 0xDF)).to eq(0x00)
          end
        end

        context 'and the data bus has bit 5 set' do
          subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

          let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
          let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
          let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil) }
          let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil) }

          it 'returns bit 5 from the data bus' do
            expect(apu.cpu_read(0x4015, 0x20)).to eq(0x20)
          end
        end
      end

      context 'and pulse 1 sounds' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: true, tick_timer: nil) }
        let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil) }

        it 'sets bit 0' do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x01)
        end
      end

      context 'and pulse 2 sounds' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil) }
        let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: true, tick_timer: nil) }

        it 'sets bit 1' do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x02)
        end
      end

      context 'and the triangle sounds' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, triangle:, noise:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, active?: true) }
        let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, active?: false) }

        it 'sets bit 2' do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x04)
        end
      end

      context 'and the noise sounds' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, triangle:, noise:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, active?: false) }
        let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, active?: true) }

        it 'sets bit 3' do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x08)
        end
      end

      context 'and the DMC has bytes remaining' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, dmc:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, active?: true, interrupt?: false, tick_timer: nil) }

        it 'sets bit 4' do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x10)
        end
      end

      context 'and the DMC interrupt flag is set' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, dmc:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
        let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, active?: false, interrupt?: true, tick_timer: nil) }

        it 'sets bit 7, leaving the flag set', :aggregate_failures do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x80)
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x80)
        end
      end

      context 'and the frame interrupt flag reads set' do
        subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
        let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: true, :cpu= => nil) }
        let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil) }
        let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil) }

        it 'sets bit 6, reading the flag on the access cycle', :aggregate_failures do
          expect(apu.cpu_read(0x4015, 0x00)).to eq(0x40)
          expect(frame_interrupt).to have_received(:read).with(9)
        end
      end

      context 'and the APU is behind the CPU' do
        context 'and no DMA halts the CPU meanwhile' do
          subject(:apu) { described_class.new(cpu:, frame_counter:, frame_interrupt:, first_pulse:, second_pulse:) }

          let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
          let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
          let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil) }
          let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, active?: false, tick_timer: nil) }

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
          let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
          let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, read: false, :cpu= => nil) }
          let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, active?: false, interrupt?: false) }

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
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil) }

      before { apu.cpu_write(0x4003, 0xF8) }

      it 'writes that register of pulse 1', :aggregate_failures do
        expect(first_pulse).to have_received(:write).with(3, 0xF8)
        expect(second_pulse).not_to have_received(:write)
      end
    end

    context 'when the address is a pulse 2 register' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, first_pulse:, second_pulse:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil) }

      before { apu.cpu_write(0x4004, 0xBF) }

      it 'writes that register of pulse 2', :aggregate_failures do
        expect(second_pulse).to have_received(:write).with(0, 0xBF)
        expect(first_pulse).not_to have_received(:write)
      end
    end

    context 'when the address is a triangle register' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, triangle:, noise:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, write: nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, write: nil) }

      before { apu.cpu_write(0x400B, 0xF8) }

      it 'writes that register of the triangle', :aggregate_failures do
        expect(triangle).to have_received(:write).with(3, 0xF8)
        expect(noise).not_to have_received(:write)
      end
    end

    context 'when the address is a noise register' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, triangle:, noise:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, write: nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, write: nil) }

      before { apu.cpu_write(0x400C, 0x30) }

      it 'writes that register of the noise', :aggregate_failures do
        expect(noise).to have_received(:write).with(0, 0x30)
        expect(triangle).not_to have_received(:write)
      end
    end

    context 'when the address is a DMC register' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, noise:, dmc:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, write: nil) }
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, write: nil, tick_timer: nil) }

      before { apu.cpu_write(0x4013, 0x01) }

      it 'writes that register of the DMC', :aggregate_failures do
        expect(dmc).to have_received(:write).with(3, 0x01)
        expect(noise).not_to have_received(:write)
      end
    end

    context 'when the address is $4015' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, :enabled= => nil, tick_timer: nil) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, :enabled= => nil, tick_timer: nil) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, :enabled= => nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, :enabled= => nil) }

      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, write_status: nil, tick_timer: nil) }

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
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, write: nil) }

      before { apu.cpu_write(0x4017, 0x40) }

      it 'writes the frame counter on the access cycle' do
        expect(frame_counter).to have_received(:write).with(0x40, 9)
      end
    end

    # OAMDMA: the bus starts OAM DMA instead (plan 11, decision 2).
    context 'when the address is $4014' do
      subject(:apu) { described_class.new(cpu:, frame_counter:, first_pulse:, second_pulse:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu, cycles: 10, access_cycle: 9) }
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, write: nil) }
      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil) }

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
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
        let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, write: nil, tick_timer: nil) }
        let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, tick_timer: nil) }

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
        let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, write: nil) }
        let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc) }

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

  describe '#catch_up' do
    context 'when the APU is behind the target cycle' do
      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }
      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, tick_timer: nil, output: 3) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, tick_timer: nil, output: 4) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, output: 5) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, output: 6) }
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, tick_timer: nil, output: 7) }

      before { apu.catch_up(5) }

      context 'and no resampler is attached' do
        subject(:apu) { described_class.new(frame_counter:, first_pulse:, second_pulse:, triangle:, noise:, dmc:) }

        it 'ticks the frame counter and triangle every cycle, the other timers on even ones', :aggregate_failures do
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

        let(:resampler) { instance_double(Ruby::Nes::Audio::Resampler, add: nil) }

        it 'adds the mix of the channels for every cycle caught up' do
          expect(resampler).to have_received(:add).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 5, 6, 7)).exactly(5).times
        end
      end
    end

    context 'when the APU already reached the target cycle' do
      subject(:apu) { described_class.new(frame_counter:).tap { |unit| unit.catch_up(5) } }

      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil) }

      it 'ticks nothing' do
        apu.catch_up(5)
        expect(frame_counter).to have_received(:tick).exactly(5).times
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
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, tick_timer: nil, half_frame: nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, tick_timer: nil, half_frame: nil) }

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

      let(:frame_counter) { instance_double(Ruby::Nes::Apu::FrameCounter, tick: nil, reset: nil) }
      let(:frame_interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, clear: nil) }
      let(:first_pulse) { instance_double(Ruby::Nes::Apu::Pulse, :enabled= => nil, tick_timer: nil) }
      let(:second_pulse) { instance_double(Ruby::Nes::Apu::Pulse, :enabled= => nil, tick_timer: nil) }
      let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, :enabled= => nil, tick_timer: nil, reset: nil) }
      let(:noise) { instance_double(Ruby::Nes::Apu::Noise, :enabled= => nil, tick_timer: nil) }
      let(:dmc) { instance_double(Ruby::Nes::Apu::Dmc, write_status: nil, tick_timer: nil, reset: nil) }

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
