# frozen_string_literal: true

require 'ruby/nes/frontends/browser'

# The ROM browser's menu (plan 37, decision 6), told each frame the buttons held on controller 1: up and down move the
# focus a ROM, left and right a page of the list's rows, each press once and then repeating while held
# (Browser::ButtonPresses); A or Start start the ROM in focus when ruby-nes can run it. The preview (Browser::Preview)
# takes the focus when it lands on another ROM, and only then, so a press against the end of the list leaves the
# preview running; it is told every frame. The focus starts on the ROM given, the first by default, the preview on it.
# Its picture is the screen of the list (Browser::Screen), with the reason the ROM in focus cannot be run: its own
# (Browser::Rom#problem), or the preview's when its cartridge cannot be loaded. A folder with no ROM is
# Browser::EmptyMenu's.
RSpec.describe Ruby::Nes::Frontends::Browser::Menu do
  describe '.new' do
    context 'when no focus is given' do
      let(:roms) { [BrowserRoms.build(name: 'BOMBERMAN II'), BrowserRoms.build(name: 'CASTLEVANIA')] }
      let(:preview) { instance_double(Ruby::Nes::Frontends::Browser::Preview, focus: nil) }

      it 'focuses the first ROM' do
        described_class.new(roms:, preview:)

        expect(preview).to have_received(:focus).with(roms.first)
      end
    end

    context 'when a focus is given' do
      let(:roms) { [BrowserRoms.build(name: 'BOMBERMAN II'), BrowserRoms.build(name: 'CASTLEVANIA')] }
      let(:preview) do
        instance_double(Ruby::Nes::Frontends::Browser::Preview, focus: nil, frame_buffer: nil, problem: nil)
      end

      it 'focuses that ROM', :aggregate_failures do
        menu = described_class.new(roms:, preview:, focus: 1)

        expect(preview).to have_received(:focus).once.with(roms.last)
        expect(ScreenText.rows(menu.picture)[20]).to eq(' ▶CASTLEVANIA                   ')
      end
    end
  end

  describe '#tick' do
    context 'when up is pressed' do
      context 'but the focus is on the first ROM' do
        subject(:menu) { described_class.new(roms:, preview:) }

        let(:roms) { [BrowserRoms.build(name: 'BOMBERMAN II'), BrowserRoms.build(name: 'CASTLEVANIA')] }
        let(:preview) do
          instance_double(
            Ruby::Nes::Frontends::Browser::Preview, focus: nil, tick: nil, frame_buffer: nil, problem: nil
          )
        end

        it 'leaves the preview on it, running', :aggregate_failures do
          menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:up))

          expect(preview).to have_received(:focus).once.with(roms.first)
          expect(preview).to have_received(:tick).once
        end
      end

      context 'and the focus is below it' do
        subject(:menu) { described_class.new(roms:, preview:) }

        let(:roms) { [BrowserRoms.build(name: 'BOMBERMAN II'), BrowserRoms.build(name: 'CASTLEVANIA')] }
        let(:preview) do
          instance_double(
            Ruby::Nes::Frontends::Browser::Preview, focus: nil, tick: nil, frame_buffer: nil, problem: nil
          )
        end

        before do
          menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:down))
          menu.tick(0)
        end

        it 'moves the focus and the preview up a ROM' do
          menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:up))

          expect(preview).to have_received(:focus).with(roms.first).twice
        end
      end
    end

    context 'when down is pressed' do
      subject(:menu) { described_class.new(roms:, preview:) }

      let(:roms) { [BrowserRoms.build(name: 'BOMBERMAN II'), BrowserRoms.build(name: 'CASTLEVANIA')] }
      let(:preview) do
        instance_double(Ruby::Nes::Frontends::Browser::Preview, focus: nil, tick: nil, frame_buffer: nil, problem: nil)
      end

      it 'moves the focus and the preview down a ROM' do
        menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:down))

        expect(preview).to have_received(:focus).with(roms.last)
      end
    end

    context 'when right is pressed' do
      subject(:menu) { described_class.new(roms:, preview:) }

      let(:roms) { Array.new(25) { BrowserRoms.build(name: "GAME #{it + 1}") } }
      let(:preview) do
        instance_double(Ruby::Nes::Frontends::Browser::Preview, focus: nil, tick: nil, frame_buffer: nil, problem: nil)
      end

      it "moves the focus and the preview down a page of the list's rows" do
        menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:right))

        expect(preview).to have_received(:focus).with(roms[10])
      end
    end

    context 'when left is pressed' do
      subject(:menu) { described_class.new(roms:, preview:) }

      let(:roms) { Array.new(25) { BrowserRoms.build(name: "GAME #{it + 1}") } }
      let(:preview) do
        instance_double(Ruby::Nes::Frontends::Browser::Preview, focus: nil, tick: nil, frame_buffer: nil, problem: nil)
      end

      before do
        menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:right))
        menu.tick(0)
        menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:right))
        menu.tick(0)
      end

      it "moves the focus and the preview up a page of the list's rows" do
        menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:left))

        expect(preview).to have_received(:focus).with(roms[10]).twice
      end
    end

    context 'when A is pressed' do
      context 'but the ROM in focus cannot be run' do
        subject(:menu) { described_class.new(roms:, preview:) }

        let(:roms) { [BrowserRoms.build(name: 'CASTLEVANIA III', problem: 'MAPPER 5 IS NOT SUPPORTED')] }
        let(:preview) do
          instance_double(
            Ruby::Nes::Frontends::Browser::Preview, focus: nil, tick: nil, frame_buffer: nil, problem: nil
          )
        end

        it 'starts nothing' do
          expect(menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:a))).to be_nil
        end
      end

      context 'and it can be run' do
        subject(:menu) { described_class.new(roms:, preview:) }

        let(:roms) { [BrowserRoms.build(name: 'CASTLEVANIA')] }
        let(:preview) do
          instance_double(
            Ruby::Nes::Frontends::Browser::Preview, focus: nil, tick: nil, frame_buffer: nil, problem: nil
          )
        end

        it 'starts it' do
          expect(menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:a))).to eq(roms.first)
        end
      end
    end

    context 'when Start is pressed' do
      context 'but the ROM in focus cannot be run' do
        subject(:menu) { described_class.new(roms:, preview:) }

        let(:roms) { [BrowserRoms.build(name: 'CASTLEVANIA III', problem: 'MAPPER 5 IS NOT SUPPORTED')] }
        let(:preview) do
          instance_double(
            Ruby::Nes::Frontends::Browser::Preview, focus: nil, tick: nil, frame_buffer: nil, problem: nil
          )
        end

        it 'starts nothing' do
          expect(menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:start))).to be_nil
        end
      end

      context 'and it can be run' do
        subject(:menu) { described_class.new(roms:, preview:) }

        let(:roms) { [BrowserRoms.build(name: 'CASTLEVANIA')] }
        let(:preview) do
          instance_double(
            Ruby::Nes::Frontends::Browser::Preview, focus: nil, tick: nil, frame_buffer: nil, problem: nil
          )
        end

        it 'starts it' do
          expect(menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:start))).to eq(roms.first)
        end
      end
    end

    context 'when nothing is pressed' do
      subject(:menu) { described_class.new(roms:, preview:) }

      let(:roms) { [BrowserRoms.build(name: 'BOMBERMAN II'), BrowserRoms.build(name: 'CASTLEVANIA')] }
      let(:preview) do
        instance_double(Ruby::Nes::Frontends::Browser::Preview, focus: nil, tick: nil, frame_buffer: nil, problem: nil)
      end

      it 'starts nothing, keeping the focus and running the preview', :aggregate_failures do
        expect(menu.tick(0)).to be_nil
        expect(preview).to have_received(:focus).once.with(roms.first)
        expect(preview).to have_received(:tick).once
      end
    end
  end

  describe '#picture' do
    context 'when the ROM in focus cannot be run' do
      subject(:menu) { described_class.new(roms:, preview:) }

      let(:roms) { [BrowserRoms.build(name: 'CASTLEVANIA III', problem: 'MAPPER 5 IS NOT SUPPORTED')] }
      let(:preview) do
        instance_double(Ruby::Nes::Frontends::Browser::Preview, focus: nil, frame_buffer: nil, problem: nil)
      end

      it "shows its reason in the preview's place" do
        expect(ScreenText.rows(menu.picture)[7]).to eq('       #MAPPER 5 IS NOT #       ')
      end
    end

    context 'when it can be run' do
      context 'but the preview cannot load its cartridge' do
        subject(:menu) { described_class.new(roms:, preview:) }

        let(:roms) { [BrowserRoms.build(name: 'SHORT')] }
        let(:preview) do
          instance_double(
            Ruby::Nes::Frontends::Browser::Preview, focus: nil, frame_buffer: nil, problem: 'IMAGE HAS 16 BYTES'
          )
        end

        it "shows the preview's reason in its place" do
          expect(ScreenText.rows(menu.picture)[7]).to eq('       #  IMAGE HAS 16  #       ')
        end
      end

      context 'and the preview loads it' do
        subject(:menu) { described_class.new(roms:, preview:) }

        let(:roms) { [BrowserRoms.build(name: 'BOMBERMAN II'), BrowserRoms.build(name: 'CASTLEVANIA')] }
        let(:preview) do
          instance_double(
            Ruby::Nes::Frontends::Browser::Preview, focus: nil, tick: nil, frame_buffer: nil, problem: nil
          )
        end

        before { menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:down)) }

        it 'is the screen of the list, the cursor on the focus' do
          expect(ScreenText.rows(menu.picture).values_at(19, 20))
            .to eq(['  BOMBERMAN II                  ', ' ▶CASTLEVANIA                   '])
        end
      end
    end
  end
end
