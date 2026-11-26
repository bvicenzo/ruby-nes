# frozen_string_literal: true

require 'ruby/nes/frontends/base'
require 'ruby/nes/frontends/driver'

# The loop every frontend shares (plan 16): while the frontend runs, the buttons it reports go to the two controllers
# (Console#controllers, plan 15), the console runs a frame, and the frontend gets the frame the PPU completed
# (Ppu#frame_buffer, plan 16, decision 1). Before a frame the console is reset when the frontend asks; a paused
# frontend gets the last completed frame again, with no frame run, so it keeps drawing and pacing (plan 18, decision
# 5). After each frame it runs, the frontend gets the frame's audio samples (Console#audio_samples) before the frame
# itself, so a frontend paced by its audio has them queued when it waits (plan 24). A frame observer (the battery save's
# keeper, plan 34) is told after each frame the driver runs. A save state action the frontend asks for goes to the
# states (Saves::StateSlots, plan 35) with the frontend, before the frame and whether paused or not.
RSpec.describe Ruby::Nes::Frontends::Driver do
  describe '#run' do
    subject(:driver) { described_class.new(console:, frontend:, frame_observer:, states:) }

    let(:frame_observer) { object_double(Ruby::Nes::Frontends::Driver::NoFrameObserver, frame_ran: nil) }
    let(:states) { object_double(Ruby::Nes::Frontends::Driver::NoStates, perform: nil) }

    let(:first_controller) { instance_double(Ruby::Nes::Input::Controller, :buttons= => nil) }
    let(:second_controller) { instance_double(Ruby::Nes::Input::Controller, :buttons= => nil) }
    let(:first_frame) { [0x0F] * 4 }
    let(:second_frame) { [0x30] * 4 }
    let(:ppu) { instance_double(Ruby::Nes::Ppu) }
    let(:console) do
      instance_double(
        Ruby::Nes::Console,
        controllers: [first_controller, second_controller],
        run_frame: nil,
        reset: nil,
        ppu:,
        audio_samples: []
      )
    end

    context 'when the frontend is not running' do
      let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, running?: false, present: nil) }

      before { driver.run }

      it 'runs no frame' do
        expect(console).not_to have_received(:run_frame)
      end

      it 'presents nothing' do
        expect(frontend).not_to have_received(:present)
      end
    end

    context 'when the frontend runs for two frames' do
      context 'but it is paused' do
        context 'and it asks for a reset' do
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base, paused?: true, state_action: nil, present: nil, button_states: [0x00, 0x00]
            )
          end

          before do
            allow(frontend).to receive(:running?).and_return(true, true, false)
            allow(frontend).to receive(:reset_requested?).and_return(true, false)
            allow(ppu).to receive(:frame_buffer).and_return(first_frame)
            driver.run
          end

          it 'resets the console' do
            expect(console).to have_received(:reset).once
          end
        end

        context 'and it asks for no reset' do
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base,
              paused?: true,
              reset_requested?: false,
              state_action: nil,
              present: nil,
              queue_audio: nil,
              button_states: [0x00, 0x00]
            )
          end

          before do
            allow(frontend).to receive(:running?).and_return(true, true, false)
            allow(ppu).to receive(:frame_buffer).and_return(first_frame)
            driver.run
          end

          it 'runs no frame' do
            expect(console).not_to have_received(:run_frame)
          end

          it 'presents the last completed frame each time' do
            expect(frontend).to have_received(:present).with(first_frame).twice
          end

          it 'queues no audio' do
            expect(frontend).not_to have_received(:queue_audio)
          end

          it 'tells the frame observer nothing' do
            expect(frame_observer).not_to have_received(:frame_ran)
          end
        end

        context 'and it asks for a save state action' do
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base,
              paused?: true,
              reset_requested?: false,
              present: nil,
              queue_audio: nil,
              button_states: [0x00, 0x00]
            )
          end

          before do
            allow(frontend).to receive(:running?).and_return(true, true, false)
            allow(frontend).to receive(:state_action).and_return(:load_state, nil)
            allow(ppu).to receive(:frame_buffer).and_return(first_frame)
            driver.run
          end

          it 'hands the action and the frontend to the states once' do
            expect(states).to have_received(:perform).with(:load_state, frontend).once
          end
        end
      end

      context 'and it is not paused' do
        context 'and it asks for a reset' do
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base,
              paused?: false,
              state_action: nil,
              present: nil,
              queue_audio: nil,
              button_states: [0x00, 0x00]
            )
          end

          before do
            allow(frontend).to receive(:running?).and_return(true, true, false)
            allow(frontend).to receive(:reset_requested?).and_return(true, false)
            allow(ppu).to receive(:frame_buffer).and_return(first_frame, second_frame)
          end

          it 'resets the console before running the frame' do
            calls = []
            allow(console).to receive(:reset) { calls << :reset }
            allow(console).to receive(:run_frame) { calls << :run_frame }
            driver.run
            expect(calls).to eq(%i[reset run_frame run_frame])
          end
        end

        context 'and it asks for no reset' do
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base,
              paused?: false,
              reset_requested?: false,
              state_action: nil,
              present: nil,
              queue_audio: nil
            )
          end

          before do
            allow(frontend).to receive(:running?).and_return(true, true, false)
            allow(frontend).to receive(:button_states).and_return([0x08, 0x00], [0x00, 0x01])
            allow(ppu).to receive(:frame_buffer).and_return(first_frame, second_frame)
          end

          it "sets both controllers' buttons, then runs the frame, each frame in turn" do
            calls = []
            allow(first_controller).to receive(:buttons=) { |buttons| calls << [:first_controller, buttons] }
            allow(second_controller).to receive(:buttons=) { |buttons| calls << [:second_controller, buttons] }
            allow(console).to receive(:run_frame) { calls << :run_frame }
            driver.run
            expect(calls).to eq(
              [
                [:first_controller, 0x08],
                [:second_controller, 0x00],
                :run_frame,
                [:first_controller, 0x00],
                [:second_controller, 0x01],
                :run_frame
              ]
            )
          end

          it 'tells the frame observer after running each frame' do
            calls = []
            allow(console).to receive(:run_frame) { calls << :run_frame }
            allow(frame_observer).to receive(:frame_ran) { calls << :frame_ran }
            driver.run
            expect(calls).to eq(%i[run_frame frame_ran run_frame frame_ran])
          end

          it 'presents each completed frame', :aggregate_failures do
            driver.run
            expect(frontend).to have_received(:present).with(first_frame).ordered
            expect(frontend).to have_received(:present).with(second_frame).ordered
          end

          it "queues each frame's audio samples after running it and before presenting it" do
            calls = []
            allow(console).to receive(:run_frame) { calls << :run_frame }
            allow(console).to receive(:audio_samples).and_return([100, -100], [200])
            allow(frontend).to receive(:queue_audio) { |samples| calls << [:queue_audio, samples] }
            allow(frontend).to receive(:present) { |frame| calls << [:present, frame] }
            driver.run
            expect(calls).to eq(
              [
                :run_frame,
                [:queue_audio, [100, -100]],
                [:present, first_frame],
                :run_frame,
                [:queue_audio, [200]],
                [:present, second_frame]
              ]
            )
          end
        end

        context 'and it asks for a save state action' do
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base,
              paused?: false,
              reset_requested?: false,
              present: nil,
              queue_audio: nil,
              button_states: [0x00, 0x00]
            )
          end

          before do
            allow(frontend).to receive(:running?).and_return(true, true, false)
            allow(frontend).to receive(:state_action).and_return(:save_state, nil)
            allow(ppu).to receive(:frame_buffer).and_return(first_frame, second_frame)
          end

          it 'hands it to the states before running the frame' do
            calls = []
            allow(states).to receive(:perform) { |action, _frontend| calls << [:perform, action] }
            allow(console).to receive(:run_frame) { calls << :run_frame }
            driver.run
            expect(calls).to eq([[:perform, :save_state], :run_frame, :run_frame])
          end
        end
      end
    end
  end
end
