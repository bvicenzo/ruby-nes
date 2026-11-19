# frozen_string_literal: true

require 'ruby/nes/frontends/base'
require 'ruby/nes/frontends/driver'

# The loop every frontend shares (plan 16): while the frontend runs, the buttons it reports go to the two controllers
# (Console#controllers, plan 15), the console runs a frame, and the frontend gets the frame the PPU completed
# (Ppu#frame_buffer, plan 16, decision 1).
RSpec.describe Ruby::Nes::Frontends::Driver do
  describe '#run' do
    subject(:driver) { described_class.new(console:, frontend:) }

    let(:first_controller) { instance_double(Ruby::Nes::Input::Controller, :buttons= => nil) }
    let(:second_controller) { instance_double(Ruby::Nes::Input::Controller, :buttons= => nil) }
    let(:first_frame) { [0x0F] * 4 }
    let(:second_frame) { [0x30] * 4 }
    let(:ppu) { instance_double(Ruby::Nes::Ppu) }
    let(:console) do
      instance_double(Ruby::Nes::Console, controllers: [first_controller, second_controller], run_frame: nil, ppu:)
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
      let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, present: nil) }

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

      it 'presents each completed frame', :aggregate_failures do
        driver.run
        expect(frontend).to have_received(:present).with(first_frame).ordered
        expect(frontend).to have_received(:present).with(second_frame).ordered
      end
    end
  end
end
