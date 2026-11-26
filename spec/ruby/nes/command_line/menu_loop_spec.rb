# frozen_string_literal: true

require 'ruby/nes/command_line'

# A menu over a paused screen in the window (plan 38): the pause menu over a game, the ROM list's menu. While the
# window runs, each frame it gets a frame of silence, unless paused, as the browser's list does (plan 37, decision 7),
# and the menu's picture; then the menu's key or buttons (Frontends::Base#menu_requested?, read as the frame was
# presented) close it as RESUME, or else the menu is told controller 1's presses (Screens::ButtonPresses) and the first
# choice ends the loop. A button held as the menu opens is no press until let go. A window that stops running ends the
# loop with no choice. Masks are in report order (Input::Controller::BUTTONS: bit 0 A).
RSpec.describe Ruby::Nes::CommandLine::MenuLoop do
  describe '.run' do
    context 'when the window stops running' do
      let(:frontend) { instance_double(Ruby::Nes::Frontends::Base, running?: false, button_states: [0, 0]) }
      let(:menu) { instance_double(Ruby::Nes::Frontends::Pause::Menu) }

      it 'chooses nothing' do
        expect(described_class.run(frontend:, menu:)).to be_nil
      end
    end

    context 'when the window runs' do
      context "and the menu's key is pressed" do
        let(:frontend) do
          instance_double(
            Ruby::Nes::Frontends::Base,
            running?: true,
            paused?: false,
            queue_silence: nil,
            present: nil,
            menu_requested?: true,
            button_states: [0, 0]
          )
        end
        let(:menu) { instance_double(Ruby::Nes::Frontends::Pause::Menu, picture: [0x0F]) }

        it "is RESUME, once the menu's picture was presented", :aggregate_failures do
          expect(described_class.run(frontend:, menu:)).to eq(Ruby::Nes::Frontends::Pause::Choice::RESUME)
          expect(frontend).to have_received(:present).with([0x0F]).once
        end
      end

      context 'and a choice is made' do
        context 'but its button was held as the menu opened' do
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base,
              paused?: false,
              queue_silence: nil,
              present: nil,
              menu_requested?: false,
              button_states: [0b0000_0001, 0]
            )
          end
          let(:menu) { instance_double(Ruby::Nes::Frontends::Pause::Menu, picture: [0x0F], tick: nil) }

          before { allow(frontend).to receive(:running?).and_return(true, false) }

          it 'tells the menu of no press' do
            described_class.run(frontend:, menu:)

            expect(menu).to have_received(:tick).with(0)
          end
        end

        context 'and the window is paused' do
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base,
              running?: true,
              paused?: true,
              queue_silence: nil,
              present: nil,
              menu_requested?: false
            )
          end
          let(:menu) { instance_double(Ruby::Nes::Frontends::Pause::Menu, picture: [0x0F]) }
          let(:choice) { Ruby::Nes::Frontends::Pause::Choice.new(action: :quit, slot: nil) }

          before do
            allow(frontend).to receive(:button_states).and_return([0, 0], [0b0000_0001, 0])
            allow(menu).to receive(:tick).with(0b0000_0001).and_return(choice)
          end

          it 'is the choice, the silence left to the window', :aggregate_failures do
            expect(described_class.run(frontend:, menu:)).to eq(choice)
            expect(frontend).not_to have_received(:queue_silence)
          end
        end

        context 'and the window is not paused' do
          let(:frontend) do
            instance_double(
              Ruby::Nes::Frontends::Base,
              running?: true,
              paused?: false,
              queue_silence: nil,
              present: nil,
              menu_requested?: false
            )
          end
          let(:menu) { instance_double(Ruby::Nes::Frontends::Pause::Menu, picture: [0x0F]) }
          let(:choice) { Ruby::Nes::Frontends::Pause::Choice.new(action: :quit, slot: nil) }

          before do
            allow(frontend).to receive(:button_states).and_return([0, 0], [0, 0], [0b0000_0001, 0])
            allow(menu).to receive(:tick).and_return(nil, choice)
          end

          it 'is the choice, a frame of silence and the picture given each frame', :aggregate_failures do
            expect(described_class.run(frontend:, menu:)).to eq(choice)
            expect(frontend).to have_received(:queue_silence).twice
            expect(frontend).to have_received(:present).twice
          end
        end
      end
    end
  end
end
