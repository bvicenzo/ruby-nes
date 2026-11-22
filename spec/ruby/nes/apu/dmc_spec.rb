# frozen_string_literal: true

# The DMC (https://www.nesdev.org/wiki/APU_DMC), its registers numbered 0-3 from $4010: `IL-- RRRR` ("Enable DMC
# sample-end interrupt", loop, "Playback rate index"), `-DDD DDDD` ("Direct counter load"), `AAAA AAAA` (sample
# address) and `LLLL LLLL` (sample length). The NTSC rates are in CPU cycles, 428, 380, 340, 320, 286, 254, 226, 214,
# 190, 160, 142, 128, 106, 84, 72, 54, and the DMC timer is clocked "only on every second CPU cycle"
# (https://www.nesdev.org/wiki/APU), so it reloads half the rate minus 1 in APU cycles; each timer clock clocks the
# output unit. A $4015 write "clears the DMC sample-end interrupt flag regardless of the written value", and its DMC bit
# starts or stops the sample; $4015 reads the sample "active" while bytes remain and the interrupt flag. Clearing the
# interrupt enable flag clears the flag. A register write takes effect on the access cycle (Cpu#access_cycle). After
# reset "[$4011] &= 1" (https://www.nesdev.org/wiki/CPU_power_up_state).
RSpec.describe Ruby::Nes::Apu::Dmc do
  # $4010 is 0 at power (https://www.nesdev.org/wiki/CPU_power_up_state): the first rate, 428 CPU cycles, 214 APU
  # cycles between timer clocks.
  describe '.new' do
    context 'when the console powers up' do
      let(:output_unit) { instance_double(Ruby::Nes::Apu::Dmc::OutputUnit, clock: nil) }

      it 'runs the timer at the first rate', :aggregate_failures do
        dmc = described_class.new(output_unit:)
        214.times { |cycle| dmc.tick_timer(cycle) }
        expect(output_unit).to have_received(:clock).once
        dmc.tick_timer(214)
        expect(output_unit).to have_received(:clock).twice
      end
    end
  end

  describe '#write' do
    context 'when the register is the first' do
      context 'and the interrupt enable flag is set' do
        subject(:dmc) { described_class.new(cpu:, interrupt:, sample:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, access_cycle: 30) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, change_inhibit: nil, :cpu= => nil) }
        let(:sample) { instance_double(Ruby::Nes::Apu::Dmc::Sample, :loop= => nil) }

        it 'lets the sample end set the interrupt flag' do
          dmc.write(0, 0x80)
          expect(interrupt).to have_received(:change_inhibit).with(false, 30)
        end
      end

      context 'and the interrupt enable flag is clear' do
        subject(:dmc) { described_class.new(cpu:, interrupt:, sample:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, access_cycle: 30) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, change_inhibit: nil, :cpu= => nil) }
        let(:sample) { instance_double(Ruby::Nes::Apu::Dmc::Sample, :loop= => nil) }

        it 'inhibits the interrupt flag, clearing it on the access cycle' do
          dmc.write(0, 0x4F)
          expect(interrupt).to have_received(:change_inhibit).with(true, 30)
        end
      end

      context 'and the loop flag is set' do
        subject(:dmc) { described_class.new(cpu:, interrupt:, sample:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, access_cycle: 30) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, change_inhibit: nil, :cpu= => nil) }
        let(:sample) { instance_double(Ruby::Nes::Apu::Dmc::Sample, :loop= => nil) }

        it 'loops the sample' do
          dmc.write(0, 0x40)
          expect(sample).to have_received(:loop=).with(true)
        end
      end

      context 'and the loop flag is clear' do
        subject(:dmc) { described_class.new(cpu:, interrupt:, sample:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, access_cycle: 30) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, change_inhibit: nil, :cpu= => nil) }
        let(:sample) { instance_double(Ruby::Nes::Apu::Dmc::Sample, :loop= => nil) }

        it 'lets the sample end' do
          dmc.write(0, 0x8F)
          expect(sample).to have_received(:loop=).with(false)
        end
      end

      context 'and the rate index is the first' do
        subject(:dmc) { described_class.new(cpu:, interrupt:, sample:, timer:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, access_cycle: 30) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, change_inhibit: nil, :cpu= => nil) }
        let(:sample) { instance_double(Ruby::Nes::Apu::Dmc::Sample, :loop= => nil) }
        let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil) }

        it 'sets the timer to 428 CPU cycles' do
          dmc.write(0, 0xC0)
          expect(timer.period).to eq(213)
        end
      end

      context 'and the rate index is the last' do
        subject(:dmc) { described_class.new(cpu:, interrupt:, sample:, timer:) }

        let(:cpu) { instance_double(Ruby::Nes::Cpu, access_cycle: 30) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, change_inhibit: nil, :cpu= => nil) }
        let(:sample) { instance_double(Ruby::Nes::Apu::Dmc::Sample, :loop= => nil) }
        let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil) }

        it 'sets the timer to 54 CPU cycles' do
          dmc.write(0, 0x0F)
          expect(timer.period).to eq(26)
        end
      end
    end

    context 'when the register is the second' do
      subject(:dmc) { described_class.new(output_unit:) }

      let(:output_unit) { instance_double(Ruby::Nes::Apu::Dmc::OutputUnit, direct_load: nil) }

      it 'loads the output level directly' do
        dmc.write(1, 0x45)
        expect(output_unit).to have_received(:direct_load).with(0x45)
      end
    end

    context 'when the register is the third' do
      subject(:dmc) { described_class.new(sample:) }

      let(:sample) { instance_double(Ruby::Nes::Apu::Dmc::Sample, :address_register= => nil) }

      it 'sets the sample address' do
        dmc.write(2, 0x12)
        expect(sample).to have_received(:address_register=).with(0x12)
      end
    end

    context 'when the register is the fourth' do
      subject(:dmc) { described_class.new(sample:) }

      let(:sample) { instance_double(Ruby::Nes::Apu::Dmc::Sample, :length_register= => nil) }

      it 'sets the sample length' do
        dmc.write(3, 0x34)
        expect(sample).to have_received(:length_register=).with(0x34)
      end
    end
  end

  describe '#tick_timer' do
    context 'when the timer clocks' do
      subject(:dmc) { described_class.new(output_unit:) }

      let(:output_unit) { instance_double(Ruby::Nes::Apu::Dmc::OutputUnit, clock: nil) }

      it 'clocks the output unit on that cycle' do
        dmc.tick_timer(42)
        expect(output_unit).to have_received(:clock).with(42)
      end
    end
  end

  describe '#write_status' do
    context 'when the DMC bit is clear' do
      subject(:dmc) { described_class.new(interrupt:, reader:) }

      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, clear: nil) }
      let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, stop: nil) }

      before { dmc.write_status(false, 50) }

      it 'clears the interrupt flag and stops the sample', :aggregate_failures do
        expect(interrupt).to have_received(:clear).with(50)
        expect(reader).to have_received(:stop)
      end
    end

    context 'when the DMC bit is set' do
      subject(:dmc) { described_class.new(interrupt:, reader:) }

      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, clear: nil) }
      let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, start: nil) }

      before { dmc.write_status(true, 50) }

      it 'clears the interrupt flag, then starts the sample on that cycle', :aggregate_failures do
        expect(interrupt).to have_received(:clear).with(50).ordered
        expect(reader).to have_received(:start).with(50).ordered
      end
    end
  end

  describe '#active?' do
    context 'when the sample has bytes remaining' do
      subject(:dmc) { described_class.new(reader:) }

      let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, active?: true) }

      it { is_expected.to be_active }
    end
  end

  describe '#interrupt?' do
    context 'when the interrupt flag is set' do
      subject(:dmc) { described_class.new(interrupt:) }

      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, flag?: true) }

      it { is_expected.to be_interrupt }
    end
  end

  describe '#output' do
    context 'when the output unit holds a level' do
      subject(:dmc) { described_class.new(output_unit:) }

      let(:output_unit) { instance_double(Ruby::Nes::Apu::Dmc::OutputUnit, output: 100) }

      it 'is that level' do
        expect(dmc.output).to eq(100)
      end
    end
  end

  describe '#reset' do
    context 'when the reset button is pressed' do
      subject(:dmc) { described_class.new(output_unit:) }

      let(:output_unit) { instance_double(Ruby::Nes::Apu::Dmc::OutputUnit, reset: nil) }

      it 'resets the output level' do
        dmc.reset
        expect(output_unit).to have_received(:reset)
      end
    end
  end

  # The Console builds the CPU and the bus after the APU.
  describe '#cpu=' do
    context 'when the console wires the CPU' do
      subject(:dmc) { described_class.new(interrupt:, reader:) }

      let(:cpu) { instance_double(Ruby::Nes::Cpu) }
      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, :cpu= => nil) }
      let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, :cpu= => nil) }

      it 'gives it to the interrupt flag and the memory reader', :aggregate_failures do
        dmc.cpu = cpu
        expect(interrupt).to have_received(:cpu=).with(cpu)
        expect(reader).to have_received(:cpu=).with(cpu)
      end
    end
  end

  describe '#memory=' do
    context 'when the console wires the bus' do
      subject(:dmc) { described_class.new(reader:) }

      let(:memory) { FlatBus.new }
      let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, :memory= => nil) }

      it 'gives it to the memory reader' do
        dmc.memory = memory
        expect(reader).to have_received(:memory=).with(memory)
      end
    end
  end
end
