# frozen_string_literal: true

# A console played frame by frame with the buttons an input script holds, keeping copies of some frames.
RSpec.describe ScriptedPlay do
  describe '#frames' do
    subject(:play) { described_class.new(console, Ruby::Nes::Frontends::InputScript.new({ 2 => 0x08, 3 => 0 })) }

    let(:console) { instance_double(Ruby::Nes::Console, controllers: [controller], run_frame: nil, ppu:) }
    let(:controller) { instance_double(Ruby::Nes::Input::Controller, :buttons= => nil) }
    let(:ppu) { instance_double(Ruby::Nes::Ppu) }

    before { allow(ppu).to receive(:frame_buffer).and_return([1], [2], [3], [4]) }

    # Nothing on frame 1, Start on frame 2, nothing again on frames 3 and 4.
    it 'holds each entry from its frame on, nothing before the first', :aggregate_failures do
      play.frames(4..4)
      expect(controller).to have_received(:buttons=).with(0x08).once
      expect(controller).to have_received(:buttons=).with(0).exactly(3).times
    end

    it 'runs up to the last frame of the range and returns copies of the range' do
      expect(play.frames(3..4)).to eq([[1], [2]])
    end
  end
end
