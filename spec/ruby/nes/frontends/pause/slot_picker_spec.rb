# frozen_string_literal: true

require 'ruby/nes/frontends/pause'
require 'ruby/nes/saves'

# The pause menu's slot picker (plan 38, scope 2): the ten save state slots, the current one in focus, navigated as a
# menu's entries (Screens::Choices). To save, every slot can be chosen; to load, only those that hold a state. Its
# picture is Pause::Screen's, with the picture of the slot in focus (Saves::StatePictures), asked the first time the
# focus lands on a slot that holds a state and kept while the picker is open, and none for an empty one. The game's slots (Saves::StateSlots) are the
# boundary: the current slot, those written, and their pictures. Masks are in report order
# (Input::Controller::BUTTONS: bit 0 A, 1 B, 5 Down).
RSpec.describe Ruby::Nes::Frontends::Pause::SlotPicker do
  describe '#tick' do
    context 'when B is pressed' do
      subject(:picker) { described_class.new(action: :save_state, slots:) }

      let(:slots) do
        instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 2, written_slots: [], pictures: pictures)
      end
      let(:pictures) { instance_double(Ruby::Nes::Saves::StatePictures) }

      it 'goes back' do
        expect(picker.tick(0b0000_0010)).to eq(Ruby::Nes::Frontends::Screens::Choices::BACK)
      end
    end

    context 'when A is pressed on an empty slot' do
      context 'and the picker loads' do
        subject(:picker) { described_class.new(action: :load_state, slots:) }

        let(:slots) do
          instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 2, written_slots: [5], pictures: pictures)
        end
        let(:pictures) { instance_double(Ruby::Nes::Saves::StatePictures) }

        it 'chooses nothing' do
          expect(picker.tick(0b0000_0001)).to be_nil
        end
      end

      context 'and the picker saves' do
        subject(:picker) { described_class.new(action: :save_state, slots:) }

        let(:slots) do
          instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 2, written_slots: [5], pictures: pictures)
        end
        let(:pictures) { instance_double(Ruby::Nes::Saves::StatePictures) }

        it 'chooses the slot' do
          expect(picker.tick(0b0000_0001)).to eq(2)
        end
      end
    end

    context 'when A is pressed on a slot with a state' do
      subject(:picker) { described_class.new(action: :load_state, slots:) }

      let(:slots) do
        instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 5, written_slots: [5], pictures: pictures)
      end
      let(:pictures) { instance_double(Ruby::Nes::Saves::StatePictures, picture: nil) }

      it 'chooses the slot' do
        expect(picker.tick(0b0000_0001)).to eq(5)
      end
    end
  end

  describe '#picture' do
    context 'when the slot in focus is empty' do
      subject(:picker) { described_class.new(action: :save_state, slots:) }

      let(:slots) do
        instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 2, written_slots: [5], pictures: pictures)
      end
      let(:pictures) { instance_double(Ruby::Nes::Saves::StatePictures, picture: nil) }

      it 'shows no picture, asking for none', :aggregate_failures do
        rows = ScreenText.rows(picker.picture)

        expect(rows[8]).to eq('       #     EMPTY      #       ')
        expect(pictures).not_to have_received(:picture)
      end
    end

    context 'when the slot in focus holds a state' do
      context 'and the focus stays on it' do
        subject(:picker) { described_class.new(action: :load_state, slots:) }

        let(:slots) do
          instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 5, written_slots: [5, 6], pictures: pictures)
        end
        let(:pictures) { instance_double(Ruby::Nes::Saves::StatePictures) }

        before do
          allow(pictures).to receive(:picture).with(5).and_return(Array.new(256 * 240, 0x21))
          picker.tick(0)
        end

        it "shows its picture, asked once, under the picker's title", :aggregate_failures do
          rows = ScreenText.rows(picker.picture)

          expect(rows[8]).to eq('       ##################       ')
          expect(rows[17]).to eq('           LOAD STATE           ')
          expect(pictures).to have_received(:picture).once
        end
      end

      context 'and the focus leaves it and comes back' do
        subject(:picker) { described_class.new(action: :load_state, slots:) }

        let(:slots) do
          instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 5, written_slots: [5, 6], pictures: pictures)
        end
        let(:pictures) { instance_double(Ruby::Nes::Saves::StatePictures) }

        before do
          allow(pictures).to receive(:picture).with(5).and_return(Array.new(256 * 240, 0x21))
          allow(pictures).to receive(:picture).with(6).and_return(Array.new(256 * 240, 0x0F))
          picker.tick(0b0010_0000)
          picker.tick(0)
          picker.tick(0b0001_0000)
        end

        it 'shows its picture, kept from the first time', :aggregate_failures do
          expect(ScreenText.rows(picker.picture)[8]).to eq('       ##################       ')
          expect(pictures).to have_received(:picture).with(5).once
        end
      end

      context 'and the focus moves to another' do
        subject(:picker) { described_class.new(action: :save_state, slots:) }

        let(:slots) do
          instance_double(Ruby::Nes::Saves::StateSlots, current_slot: 5, written_slots: [5, 6], pictures: pictures)
        end
        let(:pictures) { instance_double(Ruby::Nes::Saves::StatePictures) }

        before do
          allow(pictures).to receive(:picture).with(5).and_return(Array.new(256 * 240, 0x0F))
          allow(pictures).to receive(:picture).with(6).and_return(Array.new(256 * 240, 0x21))
          picker.tick(0b0010_0000)
        end

        it "shows the other's picture, under the picker's title", :aggregate_failures do
          rows = ScreenText.rows(picker.picture)

          expect(rows[8]).to eq('       ##################       ')
          expect(rows[17]).to eq('           SAVE STATE           ')
        end
      end
    end
  end
end
