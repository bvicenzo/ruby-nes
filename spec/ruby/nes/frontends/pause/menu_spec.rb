# frozen_string_literal: true

require 'ruby/nes/frontends/pause'

# A menu over a paused screen (plan 38): the pause menu over a game (RESUME, SAVE STATE, LOAD STATE, RESET, BACK TO THE
# LIST, QUIT) and the ROM list's (RESUME, QUIT). Told each frame the buttons pressed on controller 1, it gives what the
# player chose (Pause::Choice) once they have: B is RESUME; SAVE STATE and LOAD STATE open the slot picker
# (Pause::SlotPicker), where B returns to the entries and a slot chosen is the choice, with its slot. LOAD STATE cannot
# be chosen while no slot holds a state. Its picture is Pause::Screen's menu over the screen it opened on, dimmed
# (Screens::Shade), or the slot picker's. The game's slots (Saves::StateSlots) are the boundary. Masks are in report
# order (Input::Controller::BUTTONS: bit 0 A, 1 B, 5 Down).
RSpec.describe Ruby::Nes::Frontends::Pause::Menu do
  describe '#tick' do
    context 'when the slot picker is open' do
      context 'and B is pressed' do
        subject(:menu) { described_class.new(entries: %i[resume save_state quit], background:, slots:) }

        let(:background) { Array.new(256 * 240, 0x0F) }
        let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 0, written_slots: [], pictures: nil) }

        before do
          menu.tick(0b0010_0000)
          menu.tick(0b0000_0001)
        end

        it 'chooses nothing, the entries shown again', :aggregate_failures do
          expect(menu.tick(0b0000_0010)).to be_nil
          expect(ScreenText.rows(menu.picture)[12]).to eq('       #     PAUSED     #       ')
        end
      end

      context 'and nothing is pressed' do
        subject(:menu) { described_class.new(entries: %i[resume save_state quit], background:, slots:) }

        let(:background) { Array.new(256 * 240, 0x0F) }
        let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 3, written_slots: [], pictures: nil) }

        before do
          menu.tick(0b0010_0000)
          menu.tick(0b0000_0001)
        end

        it 'chooses nothing, the slot picker still shown', :aggregate_failures do
          expect(menu.tick(0)).to be_nil
          expect(ScreenText.rows(menu.picture)[17]).to eq('           SAVE STATE           ')
        end
      end

      context 'and a slot is chosen' do
        subject(:menu) { described_class.new(entries: %i[resume save_state quit], background:, slots:) }

        let(:background) { Array.new(256 * 240, 0x0F) }
        let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 3, written_slots: [], pictures: nil) }

        before do
          menu.tick(0b0010_0000)
          menu.tick(0b0000_0001)
        end

        it 'is the action with the slot' do
          expect(menu.tick(0b0000_0001)).to eq(Ruby::Nes::Frontends::Pause::Choice.new(action: :save_state, slot: 3))
        end
      end
    end

    context 'when the entries are shown' do
      context 'and B is pressed' do
        subject(:menu) { described_class.new(entries: %i[resume quit], background:) }

        let(:background) { Array.new(256 * 240, 0x0F) }

        it 'is RESUME' do
          expect(menu.tick(0b0000_0010)).to eq(Ruby::Nes::Frontends::Pause::Choice::RESUME)
        end
      end

      context 'and SAVE STATE is chosen' do
        subject(:menu) { described_class.new(entries: %i[resume save_state quit], background:, slots:) }

        let(:background) { Array.new(256 * 240, 0x0F) }
        let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 0, written_slots: [], pictures: nil) }

        before { menu.tick(0b0010_0000) }

        it 'chooses nothing, the slot picker open to save', :aggregate_failures do
          expect(menu.tick(0b0000_0001)).to be_nil
          expect(ScreenText.rows(menu.picture)[17]).to eq('           SAVE STATE           ')
        end
      end

      context 'and LOAD STATE is pressed' do
        context 'but no slot holds a state' do
          subject(:menu) { described_class.new(entries: %i[resume load_state quit], background:, slots:) }

          let(:background) { Array.new(256 * 240, 0x0F) }
          let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 0, written_slots: [], pictures: nil) }

          before { menu.tick(0b0010_0000) }

          it 'chooses nothing, the entries still shown', :aggregate_failures do
            expect(menu.tick(0b0000_0001)).to be_nil
            expect(ScreenText.rows(menu.picture)[12]).to eq('       #     PAUSED     #       ')
          end
        end

        context 'and a slot holds a state' do
          subject(:menu) { described_class.new(entries: %i[resume load_state quit], background:, slots:) }

          let(:background) { Array.new(256 * 240, 0x0F) }
          let(:slots) do
            instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 4, written_slots: [4], pictures: pictures)
          end
          let(:pictures) { instance_double(Ruby::Nes::Saves::StatePictures, picture: nil) }

          before { menu.tick(0b0010_0000) }

          it 'chooses nothing, the slot picker open to load', :aggregate_failures do
            expect(menu.tick(0b0000_0001)).to be_nil
            expect(ScreenText.rows(menu.picture)[17]).to eq('           LOAD STATE           ')
          end
        end
      end

      context 'and another entry is chosen' do
        subject(:menu) { described_class.new(entries: %i[resume reset quit], background:) }

        let(:background) { Array.new(256 * 240, 0x0F) }

        before { menu.tick(0b0010_0000) }

        it 'is that entry' do
          expect(menu.tick(0b0000_0001)).to eq(Ruby::Nes::Frontends::Pause::Choice.new(action: :reset, slot: nil))
        end
      end
    end
  end

  describe '#picture' do
    subject(:menu) do
      described_class.new(entries: %i[resume save_state load_state reset back_to_list quit], background:, slots:)
    end

    let(:background) { Array.new(256 * 240, 0x30) }
    let(:slots) { instance_double(Ruby::Nes::Saves::StateSlots, written_slots: [2]) }

    it 'is the entries in a box over the screen it opened on, dimmed', :aggregate_failures do
      frame = menu.picture

      expect(ScreenText.rows(frame)[9..20].map { it[7..24] }).to eq(
        [
          '##################',
          '#                #',
          '#     PAUSED     #',
          '#                #',
          '# ▶RESUME        #',
          '#  SAVE STATE    #',
          '#  LOAD STATE    #',
          '#  RESET         #',
          '#  BACK TO LIST  #',
          '#  QUIT          #',
          '#                #',
          '##################'
        ]
      )
      expect(frame[0]).to eq(0x20)
    end
  end
end
