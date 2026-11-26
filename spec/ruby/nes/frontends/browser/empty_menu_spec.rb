# frozen_string_literal: true

require 'ruby/nes/frontends/browser'

# The ROM browser's menu for a folder with no ROM (plan 37, decision 1): nothing to move through or start, whatever is
# pressed; its picture says the folder holds no ROM (Browser::Screen#empty).
RSpec.describe Ruby::Nes::Frontends::Browser::EmptyMenu do
  describe '#tick' do
    subject(:menu) { described_class.new(folder: 'roms') }

    it 'starts nothing, even on Start' do
      expect(menu.tick(Ruby::Nes::Input::Controller::BUTTONS.fetch(:start))).to be_nil
    end
  end

  describe '#picture' do
    subject(:menu) { described_class.new(folder: '/home/player/roms') }

    it 'is the screen of the empty folder' do
      expect(ScreenText.rows(menu.picture).values_at(13, 15))
        .to eq(['           NO ROMS IN           ', '       /HOME/PLAYER/ROMS        '])
    end
  end
end
