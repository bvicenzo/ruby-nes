# frozen_string_literal: true

# The APU frame counter (https://www.nesdev.org/wiki/APU_Frame_Counter), ticked once per CPU cycle with that cycle. Its
# NTSC table is in APU cycles, each step on the GET or PUT half: 2 × the APU cycle for GET, 2 × the APU cycle + 1 for
# PUT, counted in CPU cycles from the last $4017 write's effect (plan 22). Mode 0 (4-step): 7457 quarter frame, 14913
# quarter and half frame, 22371 quarter frame, 29828 interrupt flag, 29829 quarter and half frame and interrupt flag,
# 29830 interrupt flag, which is also cycle 0 of the next sequence ("every 29830 CPU cycles"). Mode 1 (5-step): 7457
# quarter, 14913 quarter and half, 22371 quarter, 29829 nothing, 37281 quarter and half, 37282 cycle 0 of the next;
# "the interrupt flag is never set". A $4017 write "resets the counter to 0" 3 CPU cycles after a write on an odd
# cycle and 4 after one on an even cycle (plan 22, decision 5), and with bit 7 set "both Quarter frame and Half frame
# clocks are also generated"; bit 6, the inhibit flag, reaches the interrupt at once. At power it acts as if $00 was
# written (https://www.nesdev.org/wiki/CPU_power_up_state): mode 0, from cycle 0. The mode 1 examples write $80 on cycle
# 0, so the sequence restarts on cycle 4, with its immediate clocks, and each step lands 4 cycles after its number.
RSpec.describe Ruby::Nes::Apu::FrameCounter do
  describe '#tick' do
    context 'when the sequence runs in mode 0' do
      context 'and the frame has not reached cycle 7457' do
        subject(:frame_counter) { described_class.new(listener:, interrupt:) }

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, trigger: nil) }

        it 'clocks nothing', :aggregate_failures do
          (1..7456).each { |cycle| frame_counter.tick(cycle) }
          expect(listener).not_to have_received(:quarter_frame)
          expect(listener).not_to have_received(:half_frame)
          expect(interrupt).not_to have_received(:trigger)
        end
      end

      context 'and the frame reaches cycle 7457' do
        subject(:frame_counter) do
          described_class.new(listener:, interrupt:).tap { |counter| (1..7456).each { |cycle| counter.tick(cycle) } }
        end

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, trigger: nil) }

        it 'clocks a quarter frame', :aggregate_failures do
          frame_counter.tick(7457)
          expect(listener).to have_received(:quarter_frame).once
          expect(listener).not_to have_received(:half_frame)
          expect(interrupt).not_to have_received(:trigger)
        end
      end

      context 'and the frame reaches cycle 14913' do
        subject(:frame_counter) do
          described_class.new(listener:, interrupt:).tap { |counter| (1..14_912).each { |cycle| counter.tick(cycle) } }
        end

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, trigger: nil) }

        it 'clocks a quarter and a half frame', :aggregate_failures do
          frame_counter.tick(14_913)
          expect(listener).to have_received(:quarter_frame).twice
          expect(listener).to have_received(:half_frame).once
          expect(interrupt).not_to have_received(:trigger)
        end
      end

      context 'and the frame reaches cycle 22371' do
        subject(:frame_counter) do
          described_class.new(listener:, interrupt:).tap { |counter| (1..22_370).each { |cycle| counter.tick(cycle) } }
        end

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, trigger: nil) }

        it 'clocks a quarter frame', :aggregate_failures do
          frame_counter.tick(22_371)
          expect(listener).to have_received(:quarter_frame).exactly(3).times
          expect(listener).to have_received(:half_frame).once
          expect(interrupt).not_to have_received(:trigger)
        end
      end

      context 'and the frame reaches cycle 29828' do
        subject(:frame_counter) do
          described_class.new(listener:, interrupt:).tap { |counter| (1..29_827).each { |cycle| counter.tick(cycle) } }
        end

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, trigger: nil) }

        it 'sets the interrupt flag only', :aggregate_failures do
          frame_counter.tick(29_828)
          expect(listener).to have_received(:quarter_frame).exactly(3).times
          expect(interrupt).to have_received(:trigger).once.with(29_828)
        end
      end

      context 'and the frame reaches cycle 29829' do
        subject(:frame_counter) do
          described_class.new(listener:, interrupt:).tap { |counter| (1..29_828).each { |cycle| counter.tick(cycle) } }
        end

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, trigger: nil) }

        it 'clocks a quarter and a half frame and sets the interrupt flag', :aggregate_failures do
          frame_counter.tick(29_829)
          expect(listener).to have_received(:quarter_frame).exactly(4).times
          expect(listener).to have_received(:half_frame).twice
          expect(interrupt).to have_received(:trigger).with(29_829)
        end
      end

      context 'and the frame reaches cycle 29830' do
        subject(:frame_counter) do
          described_class.new(listener:, interrupt:).tap { |counter| (1..29_829).each { |cycle| counter.tick(cycle) } }
        end

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, trigger: nil) }

        it 'sets the interrupt flag and starts the next sequence', :aggregate_failures do
          frame_counter.tick(29_830)
          expect(interrupt).to have_received(:trigger).with(29_830)
          (29_831..37_286).each { |cycle| frame_counter.tick(cycle) }
          expect(listener).to have_received(:quarter_frame).exactly(4).times
          frame_counter.tick(37_287)
          expect(listener).to have_received(:quarter_frame).exactly(5).times
        end
      end
    end

    context 'when the sequence runs in mode 1' do
      context 'and the frame reaches cycle 22371' do
        subject(:frame_counter) do
          described_class.new(listener:, interrupt:).tap do |counter|
            counter.write(0x80, 0)
            (1..22_374).each { |cycle| counter.tick(cycle) }
          end
        end

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, trigger: nil, change_inhibit: nil) }

        it 'clocks a quarter frame, after the ones of 7457 and 14913', :aggregate_failures do
          frame_counter.tick(22_375)
          expect(listener).to have_received(:quarter_frame).exactly(4).times
          expect(listener).to have_received(:half_frame).twice
        end
      end

      context 'and the frame reaches cycle 29829' do
        subject(:frame_counter) do
          described_class.new(listener:, interrupt:).tap do |counter|
            counter.write(0x80, 0)
            (1..29_832).each { |cycle| counter.tick(cycle) }
          end
        end

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, trigger: nil, change_inhibit: nil) }

        it 'clocks nothing and never sets the interrupt flag', :aggregate_failures do
          frame_counter.tick(29_833)
          expect(listener).to have_received(:quarter_frame).exactly(4).times
          expect(interrupt).not_to have_received(:trigger)
        end
      end

      context 'and the frame reaches cycle 37281' do
        subject(:frame_counter) do
          described_class.new(listener:, interrupt:).tap do |counter|
            counter.write(0x80, 0)
            (1..37_284).each { |cycle| counter.tick(cycle) }
          end
        end

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, trigger: nil, change_inhibit: nil) }

        it 'clocks a quarter and a half frame', :aggregate_failures do
          frame_counter.tick(37_285)
          expect(listener).to have_received(:quarter_frame).exactly(5).times
          expect(listener).to have_received(:half_frame).exactly(3).times
        end
      end

      context 'and the frame reaches cycle 37282' do
        subject(:frame_counter) do
          described_class.new(listener:, interrupt:).tap do |counter|
            counter.write(0x80, 0)
            (1..37_285).each { |cycle| counter.tick(cycle) }
          end
        end

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, trigger: nil, change_inhibit: nil) }

        it 'starts the next sequence', :aggregate_failures do
          frame_counter.tick(37_286)
          (37_287..44_742).each { |cycle| frame_counter.tick(cycle) }
          expect(listener).to have_received(:quarter_frame).exactly(5).times
          frame_counter.tick(44_743)
          expect(listener).to have_received(:quarter_frame).exactly(6).times
        end
      end
    end
  end

  describe '#write' do
    context 'when the inhibit flag is set' do
      subject(:frame_counter) { described_class.new(listener:, interrupt:) }

      let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
      let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, change_inhibit: nil) }

      it 'tells the interrupt at once' do
        frame_counter.write(0x40, 100)
        expect(interrupt).to have_received(:change_inhibit).with(true, 100)
      end
    end

    context 'when the inhibit flag is clear' do
      subject(:frame_counter) { described_class.new(listener:, interrupt:) }

      let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
      let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, change_inhibit: nil) }

      it 'tells the interrupt at once' do
        frame_counter.write(0x00, 100)
        expect(interrupt).to have_received(:change_inhibit).with(false, 100)
      end
    end

    context 'when it selects mode 1' do
      context 'and it is written on an odd cycle' do
        subject(:frame_counter) { described_class.new(listener:, interrupt:) }

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, change_inhibit: nil) }

        before do
          frame_counter.write(0x80, 101)
          (102..103).each { |cycle| frame_counter.tick(cycle) }
        end

        it 'clocks a quarter and a half frame 3 cycles later', :aggregate_failures do
          expect(listener).not_to have_received(:quarter_frame)
          frame_counter.tick(104)
          expect(listener).to have_received(:quarter_frame).once
          expect(listener).to have_received(:half_frame).once
        end

        it 'restarts the sequence then', :aggregate_failures do
          (104..7560).each { |cycle| frame_counter.tick(cycle) }
          expect(listener).to have_received(:quarter_frame).once
          frame_counter.tick(7561)
          expect(listener).to have_received(:quarter_frame).twice
        end
      end

      context 'and it is written on an even cycle' do
        subject(:frame_counter) { described_class.new(listener:, interrupt:) }

        let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, change_inhibit: nil) }

        before do
          frame_counter.write(0x80, 100)
          (101..103).each { |cycle| frame_counter.tick(cycle) }
        end

        it 'clocks a quarter and a half frame 4 cycles later', :aggregate_failures do
          expect(listener).not_to have_received(:quarter_frame)
          frame_counter.tick(104)
          expect(listener).to have_received(:quarter_frame).once
          expect(listener).to have_received(:half_frame).once
        end
      end
    end

    context 'when it selects mode 0' do
      subject(:frame_counter) do
        described_class.new(listener:, interrupt:).tap { |counter| (1..5001).each { |cycle| counter.tick(cycle) } }
      end

      let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
      let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, change_inhibit: nil) }

      before do
        frame_counter.write(0x00, 5001)
        (5002..12_460).each { |cycle| frame_counter.tick(cycle) }
      end

      it 'clocks nothing and restarts the sequence 3 cycles later', :aggregate_failures do
        expect(listener).not_to have_received(:quarter_frame)
        frame_counter.tick(12_461)
        expect(listener).to have_received(:quarter_frame).once
      end
    end

    context 'when a write is still waiting to take effect' do
      subject(:frame_counter) do
        described_class.new(listener:, interrupt:).tap { |counter| counter.write(0x80, 100) }
      end

      let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
      let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, change_inhibit: nil) }

      before do
        frame_counter.tick(101)
        frame_counter.write(0x00, 102)
        (103..106).each { |cycle| frame_counter.tick(cycle) }
      end

      it 'takes effect in its place' do
        expect(listener).not_to have_received(:quarter_frame)
      end
    end
  end

  # "At reset, same as above, except last value written to $4017 is written again, rather than $00" (apu_reset's
  # 4017_timing; plan 22, decision 4).
  describe '#reset' do
    context 'when the last write selected mode 1' do
      subject(:frame_counter) do
        described_class.new(listener:, interrupt:).tap do |counter|
          counter.write(0xC0, 101)
          (102..5000).each { |cycle| counter.tick(cycle) }
        end
      end

      let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
      let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, change_inhibit: nil) }

      before do
        frame_counter.reset(5001)
        (5002..5004).each { |cycle| frame_counter.tick(cycle) }
      end

      it 'writes it again, restarting mode 1 with its clocks', :aggregate_failures do
        expect(interrupt).to have_received(:change_inhibit).with(true, 5001)
        expect(listener).to have_received(:quarter_frame).twice
        expect(listener).to have_received(:half_frame).twice
      end
    end

    context 'when nothing was written since power' do
      subject(:frame_counter) do
        described_class.new(listener:, interrupt:).tap { |counter| (1..5001).each { |cycle| counter.tick(cycle) } }
      end

      let(:listener) { instance_double(Ruby::Nes::Apu, quarter_frame: nil, half_frame: nil) }
      let(:interrupt) { instance_double(Ruby::Nes::Apu::FrameInterrupt, change_inhibit: nil) }

      before do
        frame_counter.reset(5001)
        (5002..12_460).each { |cycle| frame_counter.tick(cycle) }
      end

      it 'writes $00, restarting mode 0', :aggregate_failures do
        expect(interrupt).to have_received(:change_inhibit).with(false, 5001)
        expect(listener).not_to have_received(:quarter_frame)
        frame_counter.tick(12_461)
        expect(listener).to have_received(:quarter_frame).once
      end
    end
  end
end
