# frozen_string_literal: true

# Builds a Ruby::Nes::Frontends::Browser::Rom, a ROM as the browser lists it (plan 37). By default it is a game ruby-nes
# can run, with no saves; each example passes only what its cause is about.
#
#   BrowserRoms.build(problem: 'MAPPER 5 IS NOT SUPPORTED')
#   BrowserRoms.build(path: 'roms/Zelda.nes', name: 'ZELDA', battery_save: true)
module BrowserRoms
  # rubocop:disable-next Metrics/ParameterLists
  def self.build(path: 'roms/Game.nes', name: 'GAME', tags: '', problem: nil, battery_save: false, save_states: false)
    Ruby::Nes::Frontends::Browser::Rom.new(path:, name:, tags:, problem:, battery_save:, save_states:)
  end
end
