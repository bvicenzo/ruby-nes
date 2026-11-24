# frozen_string_literal: true

# The channels that can change within a few cycles (plan 33): the triangle, whose timer is clocked every CPU cycle down
# to a period of 0 (https://www.nesdev.org/wiki/APU_Triangle), and the noise, whose timer is clocked on every second
# CPU cycle down to 4 CPU cycles a clock (https://www.nesdev.org/wiki/APU_Noise). Through a run of cycles in which the
# APU's slow units stand still, they go clock by clock: a stopped triangle and a silent noise skip the run, as before;
# a sequencing triangle's first clock comes `quiet_ticks` cycles from the run's start and the next ones every
# `ticks_per_clock`; a sounding noise's first clock comes on the get cycle of its `quiet_ticks`-th tick, the next ones
# every `ticks_per_clock` get cycles. Each clock inside the run steps its channel; a clock on the run's end is left to
# the next run; after the run each one moves its timer on without clocking. With a resampler the run is handed as
# parts at a level each: the mix of the slow channels' outputs, given, with the fast ones' as they stand, from the
# run's start and from each clock on. The doubles answer NEVER for a channel that cannot change.
RSpec.describe Ruby::Nes::Apu::FastChannels do
  describe '#run' do
    context 'when the triangle is stopped' do
      context 'and the noise is silent' do
        context 'and no resampler is attached' do
          subject(:fast_channels) { described_class.new(triangle:, noise:) }

          let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }
          let(:noise) { instance_double(Ruby::Nes::Apu::Noise, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }

          before { fast_channels.run(0, 5) }

          it 'skips both channels through the run, the noise by the get cycles among it', :aggregate_failures do
            expect(triangle).to have_received(:skip).once.with(5)
            expect(noise).to have_received(:skip).once.with(3)
          end
        end

        context 'and a resampler is attached' do
          subject(:fast_channels) { described_class.new(triangle:, noise:, resampler:) }

          let(:triangle) do
            instance_double(Ruby::Nes::Apu::Triangle, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 5)
          end
          let(:noise) { instance_double(Ruby::Nes::Apu::Noise, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 6) }
          let(:resampler) { instance_double(Ruby::Nes::Audio::Resampler, add_run: nil) }

          before { fast_channels.run(0, 5, 3, 4, 7) }

          it 'hands it the mix as it stands for every cycle, as one run' do
            expect(resampler).to have_received(:add_run).once.with(Ruby::Nes::Apu::Mixer.mix(3, 4, 5, 6, 7), 5)
          end
        end
      end

      # The noise's clocks every 2 get ticks are 4 CPU cycles apart, its shortest period.
      context 'and the noise sounds' do
        context 'and the run starts on a get cycle' do
          context 'and no resampler is attached' do
            subject(:fast_channels) { described_class.new(triangle:, noise:) }

            let(:triangle) do
              instance_double(Ruby::Nes::Apu::Triangle, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 5)
            end
            let(:noise) do
              instance_double(
                Ruby::Nes::Apu::Noise,
                quiet_ticks: 1,
                ticks_per_clock: 2,
                step: nil,
                skip_without_clocking: nil,
                output: 6
              )
            end

            before { fast_channels.run(0, 10) }

            it(
              'steps the noise on each clock of the run, then moves its timer on without clocking',
              :aggregate_failures
            ) do
              expect(noise).to have_received(:step).twice.ordered
              expect(noise).to have_received(:skip_without_clocking).once.with(5).ordered
              expect(triangle).to have_received(:skip).once.with(10)
            end

            it 'never asks the channels for their output', :aggregate_failures do
              expect(triangle).not_to have_received(:output)
              expect(noise).not_to have_received(:output)
            end
          end

          # Clocks on cycles 2 and 6 of a run of 10.
          context 'and a resampler is attached' do
            subject(:fast_channels) { described_class.new(triangle:, noise:, resampler:) }

            let(:triangle) do
              instance_double(Ruby::Nes::Apu::Triangle, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 5)
            end
            let(:noise) do
              instance_double(
                Ruby::Nes::Apu::Noise, quiet_ticks: 1, ticks_per_clock: 2, step: nil, skip_without_clocking: nil
              )
            end
            let(:resampler) { instance_double(Ruby::Nes::Audio::Resampler, add_run: nil) }

            before do
              allow(noise).to receive(:output).and_return(6, 0, 6)
              fast_channels.run(0, 10, 3, 4, 7)
            end

            it 'hands it the mix from each clock on, in parts', :aggregate_failures do
              expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 5, 6, 7), 2).ordered
              expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 5, 0, 7), 4).ordered
              expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 5, 6, 7), 4).ordered
              expect(resampler).to have_received(:add_run).exactly(3).times
            end
          end
        end

        # From cycle 1, the noise's first tick is on cycle 2 and its second on cycle 4: clocks on cycles 4 and 8 of a
        # run of 10.
        context 'and the run starts on a put cycle' do
          subject(:fast_channels) { described_class.new(triangle:, noise:, resampler:) }

          let(:triangle) do
            instance_double(Ruby::Nes::Apu::Triangle, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 5)
          end
          let(:noise) do
            instance_double(
              Ruby::Nes::Apu::Noise, quiet_ticks: 1, ticks_per_clock: 2, step: nil, skip_without_clocking: nil
            )
          end
          let(:resampler) { instance_double(Ruby::Nes::Audio::Resampler, add_run: nil) }

          before do
            allow(noise).to receive(:output).and_return(6, 0, 1)
            fast_channels.run(1, 10, 3, 4, 7)
          end

          it 'steps the noise on the clocks of its get cycles', :aggregate_failures do
            expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 5, 6, 7), 3).ordered
            expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 5, 0, 7), 4).ordered
            expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 5, 1, 7), 3).ordered
            expect(noise).to have_received(:skip_without_clocking).once.with(5)
          end
        end

        # Clocks on cycles 2 and 6, a run of 6.
        context "and a clock falls on the run's end" do
          subject(:fast_channels) { described_class.new(triangle:, noise:) }

          let(:triangle) { instance_double(Ruby::Nes::Apu::Triangle, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }
          let(:noise) do
            instance_double(
              Ruby::Nes::Apu::Noise, quiet_ticks: 1, ticks_per_clock: 2, step: nil, skip_without_clocking: nil
            )
          end

          before { fast_channels.run(0, 6) }

          it 'leaves that clock to the next run', :aggregate_failures do
            expect(noise).to have_received(:step).once
            expect(noise).to have_received(:skip_without_clocking).once.with(3)
          end
        end
      end
    end

    context 'when the triangle sequences' do
      context 'and the noise is silent' do
        # A clock on cycle 0, the next one past a run of 4.
        context "and its first clock is on the run's first cycle" do
          subject(:fast_channels) { described_class.new(triangle:, noise:, resampler:) }

          let(:triangle) do
            instance_double(
              Ruby::Nes::Apu::Triangle, quiet_ticks: 0, ticks_per_clock: 5, step: nil, skip_without_clocking: nil
            )
          end
          let(:noise) { instance_double(Ruby::Nes::Apu::Noise, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 6) }
          let(:resampler) { instance_double(Ruby::Nes::Audio::Resampler, add_run: nil) }

          before do
            allow(triangle).to receive(:output).and_return(15, 14)
            fast_channels.run(0, 4, 3, 4, 7)
          end

          it "steps it on that cycle, the new mix standing from the run's first cycle", :aggregate_failures do
            expect(triangle).to have_received(:step).once
            expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 14, 6, 7), 4)
            expect(resampler).not_to have_received(:add_run)
              .with(Ruby::Nes::Apu::Mixer.mix(3, 4, 15, 6, 7), be_positive)
          end
        end

        # Clocks on cycles 2, 5 and 8 of a run of 10.
        context 'and its clocks fall within the run' do
          context 'and no resampler is attached' do
            subject(:fast_channels) { described_class.new(triangle:, noise:) }

            let(:triangle) do
              instance_double(
                Ruby::Nes::Apu::Triangle, quiet_ticks: 2, ticks_per_clock: 3, step: nil, skip_without_clocking: nil
              )
            end
            let(:noise) { instance_double(Ruby::Nes::Apu::Noise, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }

            before { fast_channels.run(0, 10) }

            it 'steps the triangle on each clock, then moves its timer on without clocking', :aggregate_failures do
              expect(triangle).to have_received(:step).exactly(3).times.ordered
              expect(triangle).to have_received(:skip_without_clocking).once.with(10).ordered
              expect(noise).to have_received(:skip).once.with(5)
            end
          end

          context 'and a resampler is attached' do
            subject(:fast_channels) { described_class.new(triangle:, noise:, resampler:) }

            let(:triangle) do
              instance_double(
                Ruby::Nes::Apu::Triangle, quiet_ticks: 2, ticks_per_clock: 3, step: nil, skip_without_clocking: nil
              )
            end
            let(:noise) { instance_double(Ruby::Nes::Apu::Noise, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil, output: 6) }
            let(:resampler) { instance_double(Ruby::Nes::Audio::Resampler, add_run: nil) }

            before do
              allow(triangle).to receive(:output).and_return(15, 14, 13, 12)
              fast_channels.run(0, 10, 3, 4, 7)
            end

            it 'hands it the mix from each clock on, in parts', :aggregate_failures do
              expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 15, 6, 7), 2).ordered
              expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 14, 6, 7), 3).ordered
              expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 13, 6, 7), 3).ordered
              expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 12, 6, 7), 2).ordered
              expect(resampler).to have_received(:add_run).exactly(4).times
            end
          end
        end

        # Clocks on cycles 2 and 6, a run of 6.
        context "and a clock falls on the run's end" do
          subject(:fast_channels) { described_class.new(triangle:, noise:) }

          let(:triangle) do
            instance_double(
              Ruby::Nes::Apu::Triangle, quiet_ticks: 2, ticks_per_clock: 4, step: nil, skip_without_clocking: nil
            )
          end
          let(:noise) { instance_double(Ruby::Nes::Apu::Noise, quiet_ticks: Ruby::Nes::Apu::NEVER, skip: nil) }

          before { fast_channels.run(0, 6) }

          it 'leaves that clock to the next run', :aggregate_failures do
            expect(triangle).to have_received(:step).once
            expect(triangle).to have_received(:skip_without_clocking).once.with(6)
          end
        end
      end

      context 'and the noise sounds' do
        # Both clock on cycle 2 of a run of 4.
        context 'and both clock on the same cycle' do
          subject(:fast_channels) { described_class.new(triangle:, noise:, resampler:) }

          let(:triangle) do
            instance_double(
              Ruby::Nes::Apu::Triangle, quiet_ticks: 2, ticks_per_clock: 4, step: nil, skip_without_clocking: nil
            )
          end
          let(:noise) do
            instance_double(
              Ruby::Nes::Apu::Noise, quiet_ticks: 1, ticks_per_clock: 2, step: nil, skip_without_clocking: nil
            )
          end
          let(:resampler) { instance_double(Ruby::Nes::Audio::Resampler, add_run: nil) }

          before do
            allow(triangle).to receive(:output).and_return(15, 14)
            allow(noise).to receive(:output).and_return(6, 0)
            fast_channels.run(0, 4, 3, 4, 7)
          end

          it 'steps both, and the mix changes once', :aggregate_failures do
            expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 15, 6, 7), 2).ordered
            expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 14, 0, 7), 2).ordered
            expect(resampler).to have_received(:add_run).twice
            expect(triangle).to have_received(:step).once
            expect(noise).to have_received(:step).once
          end
        end

        # The triangle clocks on cycles 1 and 5, the noise on cycles 2 and 6, in a run of 8.
        context 'and their clocks alternate' do
          subject(:fast_channels) { described_class.new(triangle:, noise:, resampler:) }

          let(:triangle) do
            instance_double(
              Ruby::Nes::Apu::Triangle, quiet_ticks: 1, ticks_per_clock: 4, step: nil, skip_without_clocking: nil
            )
          end
          let(:noise) do
            instance_double(
              Ruby::Nes::Apu::Noise, quiet_ticks: 1, ticks_per_clock: 2, step: nil, skip_without_clocking: nil
            )
          end
          let(:resampler) { instance_double(Ruby::Nes::Audio::Resampler, add_run: nil) }

          before do
            allow(triangle).to receive(:output).and_return(15, 14, 13)
            allow(noise).to receive(:output).and_return(6, 0, 6)
            fast_channels.run(0, 8, 3, 4, 7)
          end

          it 'steps each in cycle order, the mix handed after each', :aggregate_failures do
            expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 15, 6, 7), 1).ordered
            expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 14, 6, 7), 1).ordered
            expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 14, 0, 7), 3).ordered
            expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 13, 0, 7), 1).ordered
            expect(resampler).to have_received(:add_run).with(Ruby::Nes::Apu::Mixer.mix(3, 4, 13, 6, 7), 2).ordered
          end
        end

        # Real channels, against the same channels run cycle by cycle as Apu#run_cycle runs them (the triangle's timer
        # every cycle, the noise's on even ones, then the mix): $4008 = $81 (control, a linear counter of 1), $400A and
        # $400B = $00 and $08 (period 0, a length), $400C = $3F (constant volume 15), $400E = $00 (4 CPU cycles), $400F
        # = $08, both enabled. Two runs from an odd cycle, the first ending between the noise's clocks.
        context 'and they are a triangle at period 0 and a noise at its shortest period' do
          subject(:fast_channels) { described_class.new(triangle:, noise:, resampler:) }

          let(:triangle) do
            Ruby::Nes::Apu::Triangle.new.tap do |channel|
              channel.enabled = true
              [[0, 0x81], [2, 0x00], [3, 0x08]].each { |register, value| channel.write(register, value) }
              channel.quarter_frame
            end
          end
          let(:noise) do
            Ruby::Nes::Apu::Noise.new.tap do |channel|
              channel.enabled = true
              [[0, 0x3F], [2, 0x00], [3, 0x08]].each { |register, value| channel.write(register, value) }
            end
          end
          let(:resampler) { Ruby::Nes::Audio::Resampler.new(output_rate: 3, output:, input_rate: 10) }
          let(:output) { Ruby::Nes::Audio::SampleBuffer.new }
          let(:cycle_by_cycle_triangle) do
            Ruby::Nes::Apu::Triangle.new.tap do |channel|
              channel.enabled = true
              [[0, 0x81], [2, 0x00], [3, 0x08]].each { |register, value| channel.write(register, value) }
              channel.quarter_frame
            end
          end
          let(:cycle_by_cycle_noise) do
            Ruby::Nes::Apu::Noise.new.tap do |channel|
              channel.enabled = true
              [[0, 0x3F], [2, 0x00], [3, 0x08]].each { |register, value| channel.write(register, value) }
            end
          end
          let(:cycle_by_cycle) { Ruby::Nes::Audio::Resampler.new(output_rate: 3, output: cycle_by_cycle_output, input_rate: 10) }
          let(:cycle_by_cycle_output) { Ruby::Nes::Audio::SampleBuffer.new }

          before do
            fast_channels.run(1, 77, 3, 4, 7)
            fast_channels.run(78, 123, 3, 4, 7)
            # Cycles 1-200 by pairs: an odd cycle ticks the triangle alone, the even one after it both.
            100.times do
              cycle_by_cycle_triangle.tick_timer
              cycle_by_cycle.add(
                Ruby::Nes::Apu::Mixer.mix(3, 4, cycle_by_cycle_triangle.output, cycle_by_cycle_noise.output, 7)
              )
              cycle_by_cycle_triangle.tick_timer
              cycle_by_cycle_noise.tick_timer
              cycle_by_cycle.add(
                Ruby::Nes::Apu::Mixer.mix(3, 4, cycle_by_cycle_triangle.output, cycle_by_cycle_noise.output, 7)
              )
            end
          end

          it 'hands the levels running the cycles one by one would', :aggregate_failures do
            levels = output.drain
            expect(levels.size).to eq(60)
            expect(levels).to eq(cycle_by_cycle_output.drain)
            expect([triangle.output, noise.output]).to eq([cycle_by_cycle_triangle.output, cycle_by_cycle_noise.output])
          end
        end
      end
    end
  end
end
