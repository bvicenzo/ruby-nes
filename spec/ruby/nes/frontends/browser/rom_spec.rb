# frozen_string_literal: true

require 'ruby/nes/frontends/browser'

# A ROM the browser lists (plan 37, scope 2) is started only when nothing keeps ruby-nes from running it.
RSpec.describe Ruby::Nes::Frontends::Browser::Rom do
  describe '#playable?' do
    context 'when the ROM has a problem' do
      subject(:rom) do
        described_class.new(
          path: 'roms/Castlevania III.nes',
          name: 'CASTLEVANIA III',
          tags: '',
          problem: 'MAPPER 5 IS NOT SUPPORTED',
          battery_save: false,
          save_states: false
        )
      end

      it 'is false' do
        expect(rom).not_to be_playable
      end
    end

    context 'when the ROM has none' do
      subject(:rom) do
        described_class.new(
          path: 'roms/Castlevania.nes',
          name: 'CASTLEVANIA',
          tags: '',
          problem: nil,
          battery_save: false,
          save_states: false
        )
      end

      it 'is true' do
        expect(rom).to be_playable
      end
    end
  end
end
