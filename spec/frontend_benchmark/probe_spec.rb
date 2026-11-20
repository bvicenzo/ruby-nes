# frozen_string_literal: true

require_relative '../../bench/frontend_benchmark'

# A frontend wrapped to be measured (plan 17): it stops after a number of frames, times each present and the interval
# between frames, and queues a frame's worth of an audio source after each present.
RSpec.describe FrontendBenchmark::Probe do
  describe '#running?' do
    let(:audio) { FrontendBenchmark::SquareWave.new(frequency: 1, sample_rate: 8, amplitude: 0) }

    context 'when a frame limit is given' do
      context 'and fewer frames were presented' do
        context 'but the frontend stopped' do
          subject(:probe) { described_class.new(frontend, audio:, samples_per_frame: 4, frames: 2) }

          let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, running?: false) }

          it 'is false' do
            expect(probe).not_to be_running
          end
        end

        context 'and the frontend runs' do
          subject(:probe) { described_class.new(frontend, audio:, samples_per_frame: 4, frames: 2) }

          let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, running?: true, present: nil, queue_audio: nil) }

          before { probe.present([0x0F]) }

          it 'is true' do
            expect(probe).to be_running
          end
        end
      end

      context 'and as many frames were presented' do
        subject(:probe) { described_class.new(frontend, audio:, samples_per_frame: 4, frames: 2) }

        let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, running?: true, present: nil, queue_audio: nil) }

        before do
          probe.present([0x0F])
          probe.present([0x0F])
        end

        it 'is false' do
          expect(probe).not_to be_running
        end
      end
    end

    context 'when no frame limit is given' do
      context 'but the frontend stopped' do
        subject(:probe) { described_class.new(frontend, audio:, samples_per_frame: 4) }

        let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, running?: false) }

        it 'is false' do
          expect(probe).not_to be_running
        end
      end

      context 'and the frontend runs' do
        subject(:probe) { described_class.new(frontend, audio:, samples_per_frame: 4) }

        let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, running?: true) }

        it 'is true' do
          expect(probe).to be_running
        end
      end
    end
  end

  describe '#button_states' do
    subject(:probe) { described_class.new(frontend, audio:, samples_per_frame: 4) }

    let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, button_states: [0x08, 0x01]) }
    let(:audio) { FrontendBenchmark::SquareWave.new(frequency: 1, sample_rate: 8, amplitude: 0) }

    it "is the frontend's" do
      expect(probe.button_states).to eq([0x08, 0x01])
    end
  end

  describe '#queue_audio' do
    subject(:probe) { described_class.new(frontend, audio:, samples_per_frame: 4) }

    let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, queue_audio: nil) }
    let(:audio) { FrontendBenchmark::SquareWave.new(frequency: 1, sample_rate: 8, amplitude: 0) }

    it 'passes the samples to the frontend' do
      probe.queue_audio([1, -1])

      expect(frontend).to have_received(:queue_audio).with([1, -1])
    end
  end

  describe '#present' do
    subject(:probe) { described_class.new(frontend, audio:, samples_per_frame: 4) }

    let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, present: nil, queue_audio: nil) }
    let(:audio) { FrontendBenchmark::SquareWave.new(frequency: 1, sample_rate: 8, amplitude: 100) }

    it 'presents the frame buffer on the frontend' do
      probe.present([0x0F, 0x30])

      expect(frontend).to have_received(:present).with([0x0F, 0x30])
    end

    it "queues a frame's worth of the audio source on the frontend" do
      probe.present([0x0F])

      expect(frontend).to have_received(:queue_audio).with([100, 100, 100, 100])
    end
  end

  describe '#present_seconds' do
    subject(:probe) { described_class.new(frontend, audio:, samples_per_frame: 4, clock:) }

    let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, present: nil, queue_audio: nil) }
    let(:audio) { FrontendBenchmark::SquareWave.new(frequency: 1, sample_rate: 8, amplitude: 0) }
    let(:clock) { instance_double(Proc) }

    before { allow(clock).to receive(:call).and_return(1.0, 1.25, 1.5, 1.625) }

    it 'holds how long each present took' do
      probe.present([0x0F])
      probe.present([0x0F])

      expect(probe.present_seconds).to eq([0.25, 0.125])
    end
  end

  describe '#frame_seconds' do
    subject(:probe) { described_class.new(frontend, audio:, samples_per_frame: 4, clock:) }

    let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, present: nil, queue_audio: nil) }
    let(:audio) { FrontendBenchmark::SquareWave.new(frequency: 1, sample_rate: 8, amplitude: 0) }
    let(:clock) { instance_double(Proc) }

    context 'when one frame was presented' do
      before do
        allow(clock).to receive(:call).and_return(1.0, 1.25)
        probe.present([0x0F])
      end

      it 'holds none' do
        expect(probe.frame_seconds).to eq([])
      end
    end

    context 'when frames were presented' do
      before do
        allow(clock).to receive(:call).and_return(1.0, 1.25, 1.5, 1.625)
        probe.present([0x0F])
        probe.present([0x0F])
      end

      it "holds the time from each present's start to the next one's" do
        expect(probe.frame_seconds).to eq([0.5])
      end
    end
  end
end
