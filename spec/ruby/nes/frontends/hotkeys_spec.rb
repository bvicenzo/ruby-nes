# frozen_string_literal: true

require 'ruby/nes/frontends/hotkeys'

# The keys that drive the emulator rather than the controller (plan 18, decision 6): quit, pause, reset and the frame
# rate overlay, the save states' (plan 35, decision 3) and the menu's (plan 38, decision 2). A windowed frontend tells it
# once per frame which bound keys were pressed during that frame; pause and the overlay toggle on each frame their key
# is pressed, reset, the menu and a state action are asked for during that frame only, quit stays asked. The ROM browser starts them over between screens
# (plan 37, decision 7), keeping the overlay as the player left it.
# Key codes here are arbitrary integers, as each graphics library numbers its keys its own way.
RSpec.describe Ruby::Nes::Frontends::Hotkeys do
  describe '.new' do
    context 'when a binding names something that is not an action' do
      let(:bindings) { { 80 => :pause, 83 => :rewind, 87 => :fast_forward } }

      it 'raises ArgumentError naming it' do
        expect { described_class.new(bindings) }.to raise_error(ArgumentError, /rewind, fast_forward/)
      end
    end

    context 'when every binding names an action' do
      let(:bindings) { { 80 => :pause, 82 => :reset, 256 => :quit, 70 => :frame_rate, 27 => :menu } }

      it 'builds hotkeys' do
        expect { described_class.new(bindings) }.not_to raise_error
      end
    end
  end

  describe '#quit?' do
    subject(:hotkeys) { described_class.new({ 256 => :quit, 80 => :pause }) }

    context 'when no quit key has been pressed' do
      before { hotkeys.poll { |key_code| key_code == 80 } }

      it 'is false' do
        expect(hotkeys).not_to be_quit
      end
    end

    context 'when a quit key has been pressed' do
      before do
        hotkeys.poll { |key_code| key_code == 256 }
        hotkeys.poll { false }
      end

      it 'is true' do
        expect(hotkeys).to be_quit
      end
    end
  end

  describe '#paused?' do
    subject(:hotkeys) { described_class.new({ 80 => :pause, 19 => :pause, 82 => :reset }) }

    context 'when no pause key has been pressed' do
      before { hotkeys.poll { |key_code| key_code == 82 } }

      it 'is false' do
        expect(hotkeys).not_to be_paused
      end
    end

    context 'when a pause key has been pressed once' do
      before do
        hotkeys.poll { |key_code| key_code == 80 }
        hotkeys.poll { false }
      end

      it 'is true' do
        expect(hotkeys).to be_paused
      end
    end

    context 'when pause keys have been pressed in two polls' do
      before do
        hotkeys.poll { |key_code| key_code == 80 }
        hotkeys.poll { |key_code| key_code == 19 }
      end

      it 'is false' do
        expect(hotkeys).not_to be_paused
      end
    end

    context 'when two pause keys are pressed in one poll' do
      before { hotkeys.poll { |key_code| [80, 19].include?(key_code) } }

      it 'is true' do
        expect(hotkeys).to be_paused
      end
    end
  end

  describe '#reset_requested?' do
    subject(:hotkeys) { described_class.new({ 82 => :reset, 80 => :pause }) }

    context 'when no reset key has been pressed' do
      before { hotkeys.poll { |key_code| key_code == 80 } }

      it 'is false' do
        expect(hotkeys).not_to be_reset_requested
      end
    end

    context 'when the last poll pressed a reset key' do
      before { hotkeys.poll { |key_code| key_code == 82 } }

      it 'is true' do
        expect(hotkeys).to be_reset_requested
      end
    end

    context 'when only an earlier poll pressed a reset key' do
      before do
        hotkeys.poll { |key_code| key_code == 82 }
        hotkeys.poll { false }
      end

      it 'is false' do
        expect(hotkeys).not_to be_reset_requested
      end
    end
  end

  describe '#menu_requested?' do
    subject(:hotkeys) { described_class.new({ 256 => :menu, 80 => :pause }) }

    context 'when no menu key has been pressed' do
      before { hotkeys.poll { |key_code| key_code == 80 } }

      it 'is false' do
        expect(hotkeys).not_to be_menu_requested
      end
    end

    context 'when the last poll pressed a menu key' do
      before { hotkeys.poll { |key_code| key_code == 256 } }

      it 'is true' do
        expect(hotkeys).to be_menu_requested
      end
    end

    context 'when only an earlier poll pressed a menu key' do
      before do
        hotkeys.poll { |key_code| key_code == 256 }
        hotkeys.poll { false }
      end

      it 'is false' do
        expect(hotkeys).not_to be_menu_requested
      end
    end
  end

  describe '#frame_rate_shown?' do
    subject(:hotkeys) { described_class.new({ 70 => :frame_rate, 80 => :pause }) }

    context 'when no frame rate key has been pressed' do
      before { hotkeys.poll { |key_code| key_code == 80 } }

      it 'is true' do
        expect(hotkeys).to be_frame_rate_shown
      end
    end

    context 'when a frame rate key has been pressed once' do
      before do
        hotkeys.poll { |key_code| key_code == 70 }
        hotkeys.poll { false }
      end

      it 'is false' do
        expect(hotkeys).not_to be_frame_rate_shown
      end
    end

    context 'when frame rate keys have been pressed in two polls' do
      before { 2.times { hotkeys.poll { |key_code| key_code == 70 } } }

      it 'is true' do
        expect(hotkeys).to be_frame_rate_shown
      end
    end
  end

  # Saving, loading, and the previous and next slot (Saves::StateSlots::ACTIONS); one action a frame, the first of them
  # in that order when several keys were pressed together.
  describe '#state_action' do
    subject(:hotkeys) { described_class.new(bindings) }

    let(:bindings) do
      { 116 => :save_state, 118 => :load_state, 117 => :previous_slot, 119 => :next_slot, 80 => :pause }
    end

    context 'when no state key has been pressed' do
      before { hotkeys.poll { |key_code| key_code == 80 } }

      it 'is nil' do
        expect(hotkeys.state_action).to be_nil
      end
    end

    context 'when the last poll pressed a state key' do
      context 'and it is the save key' do
        before { hotkeys.poll { |key_code| key_code == 116 } }

        it 'is save_state' do
          expect(hotkeys.state_action).to eq(:save_state)
        end
      end

      context 'and it is the load key' do
        before { hotkeys.poll { |key_code| key_code == 118 } }

        it 'is load_state' do
          expect(hotkeys.state_action).to eq(:load_state)
        end
      end

      context 'and it is the previous slot key' do
        before { hotkeys.poll { |key_code| key_code == 117 } }

        it 'is previous_slot' do
          expect(hotkeys.state_action).to eq(:previous_slot)
        end
      end

      context 'and it is the next slot key' do
        before { hotkeys.poll { |key_code| key_code == 119 } }

        it 'is next_slot' do
          expect(hotkeys.state_action).to eq(:next_slot)
        end
      end

      context 'and the load and the save keys were both pressed' do
        before { hotkeys.poll { |key_code| [118, 116].include?(key_code) } }

        it 'is save_state' do
          expect(hotkeys.state_action).to eq(:save_state)
        end
      end
    end

    context 'when only an earlier poll pressed a state key' do
      before do
        hotkeys.poll { |key_code| key_code == 116 }
        hotkeys.poll { false }
      end

      it 'is nil' do
        expect(hotkeys.state_action).to be_nil
      end
    end
  end

  describe '#restart' do
    subject(:hotkeys) do
      described_class.new(
        { 256 => :quit, 80 => :pause, 82 => :reset, 70 => :frame_rate, 116 => :save_state, 27 => :menu }
      )
    end

    before { hotkeys.poll { true } }

    it 'starts over, not quitting, not paused and asking nothing, the overlay as it was', :aggregate_failures do
      hotkeys.restart

      expect(hotkeys).to have_attributes(
        quit?: false,
        paused?: false,
        reset_requested?: false,
        menu_requested?: false,
        state_action: nil,
        frame_rate_shown?: false
      )
    end
  end
end
