# frozen_string_literal: true

require_relative '../../bench/frame_benchmark'

require 'digest'
require 'tempfile'

# The workload plays the console as the window does: the first controller's buttons from the input script, counted
# from frame 1 (Frontends::InputScript::FIRST_FRAME), then a frame, then the frame's audio drained.
RSpec.describe FrameBenchmark::Workload do
  # The console plays with audio at the window's sample rate (plan 25, decision 2), so a frame drains samples.
  describe '.from_files', test_rom: [Nestest::ROM_PATH] do
    let(:input_script) do
      Tempfile.create(['input', '.yml']).tap do |file|
        file.write("1: [start]\n")
        file.close
      end
    end

    after { File.delete(input_script.path) }

    it "plays the ROM with the script's input and the audio on" do
      workload = described_class.from_files(rom: test_rom_path(Nestest::ROM_PATH), input: input_script.path)
      workload.run(frames: 1)
      expect(workload.audio_digest).not_to eq(Digest::SHA256.hexdigest(''))
    end
  end

  describe '#run' do
    context 'when no frames are asked' do
      subject(:workload) { described_class.new(console, input_script: Ruby::Nes::Frontends::InputScript::EMPTY) }

      let(:console) { instance_double(Ruby::Nes::Console, run_frame: nil) }

      it 'plays no frame, in no time', :aggregate_failures do
        expect(workload.run(frames: 0)).to eq(FrameBenchmark::Sample.new(frames: 0, seconds: 0.0))
        expect(console).not_to have_received(:run_frame)
      end
    end

    context 'when frames are asked' do
      context 'and it is the first run' do
        subject(:workload) { described_class.new(console, input_script:, clock:) }

        let(:controller) { instance_double(Ruby::Nes::Input::Controller, 'buttons=': nil) }
        let(:console) do
          instance_double(Ruby::Nes::Console, controllers: [controller], run_frame: nil, audio_samples: [])
        end
        let(:input_script) { Ruby::Nes::Frontends::InputScript.parse("1: [a]\n2: [start]\n3: [b]\n") }
        # Each frame is read between two clock readings: 1, 2 and 4 seconds, with gaps between frames that must not
        # count.
        let(:clock) { [0.0, 1.0, 10.0, 12.0, 20.0, 24.0].each.method(:next) }

        it 'plays that many frames' do
          workload.run(frames: 3)
          expect(console).to have_received(:run_frame).exactly(3).times
        end

        it "holds, on each frame, the script's buttons for its number, counted from 1", :aggregate_failures do
          workload.run(frames: 3)
          expect(controller).to have_received(:buttons=).with(Ruby::Nes::Input::Controller::BUTTONS[:a]).ordered
          expect(controller).to have_received(:buttons=).with(Ruby::Nes::Input::Controller::BUTTONS[:start]).ordered
          expect(controller).to have_received(:buttons=).with(Ruby::Nes::Input::Controller::BUTTONS[:b]).ordered
        end

        it 'drains the audio after each frame' do
          workload.run(frames: 3)
          expect(console).to have_received(:audio_samples).exactly(3).times
        end

        it 'times only the frames' do
          expect(workload.run(frames: 3)).to eq(FrameBenchmark::Sample.new(frames: 3, seconds: 7.0))
        end
      end

      context 'and an earlier run played frames' do
        subject(:workload) { described_class.new(console, input_script:) }

        let(:controller) { instance_double(Ruby::Nes::Input::Controller, 'buttons=': nil) }
        let(:console) do
          instance_double(Ruby::Nes::Console, controllers: [controller], run_frame: nil, audio_samples: [])
        end
        let(:input_script) { Ruby::Nes::Frontends::InputScript.parse("3: [a]\n") }

        before { workload.run(frames: 2) }

        it 'goes on with the frame numbers where that run stopped' do
          workload.run(frames: 1)
          expect(controller).to have_received(:buttons=).with(Ruby::Nes::Input::Controller::BUTTONS[:a]).once
        end
      end
    end
  end

  describe '#frame_digest' do
    subject(:workload) { described_class.new(console, input_script: Ruby::Nes::Frontends::InputScript::EMPTY) }

    let(:controller) { instance_double(Ruby::Nes::Input::Controller, 'buttons=': nil) }
    let(:ppu) { instance_double(Ruby::Nes::Ppu, frame_buffer: [0x1FF, 0x0F]) }
    let(:console) do
      instance_double(Ruby::Nes::Console, controllers: [controller], run_frame: nil, audio_samples: [], ppu:)
    end

    before { workload.run(frames: 2) }

    # The console's frame buffer is its last complete frame; the pixels 0x1FF and 0x0F as 16-bit little-endian
    # integers: FF 01 0F 00.
    it "is the SHA-256 of the last frame's pixels as 16-bit little-endian integers" do
      expect(workload.frame_digest).to eq(Digest::SHA256.hexdigest("\xFF\x01\x0F\x00".b))
    end
  end

  describe '#audio_digest' do
    context 'when no sample was drained' do
      subject(:workload) { described_class.new(console, input_script: Ruby::Nes::Frontends::InputScript::EMPTY) }

      let(:console) { instance_double(Ruby::Nes::Console) }

      it 'is the SHA-256 of nothing' do
        expect(workload.audio_digest).to eq(Digest::SHA256.hexdigest(''))
      end
    end

    context 'when samples were drained over several runs' do
      subject(:workload) { described_class.new(console, input_script: Ruby::Nes::Frontends::InputScript::EMPTY) }

      let(:controller) { instance_double(Ruby::Nes::Input::Controller, 'buttons=': nil) }
      let(:console) { instance_double(Ruby::Nes::Console, controllers: [controller], run_frame: nil) }

      before do
        allow(console).to receive(:audio_samples).and_return([1, -1], [-32_768])
        workload.run(frames: 1)
        workload.run(frames: 1)
      end

      # 1, -1 and -32768 as signed 16-bit little-endian integers: 01 00, FF FF, 00 80.
      it 'is the SHA-256 of all of them in order, as signed 16-bit little-endian' do
        expect(workload.audio_digest).to eq(Digest::SHA256.hexdigest("\x01\x00\xFF\xFF\x00\x80".b))
      end
    end
  end
end
