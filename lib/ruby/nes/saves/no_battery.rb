# frozen_string_literal: true

module Ruby
  module Nes
    module Saves
      # The keeper of a console without battery RAM (Saves::BatteryKeeper.for): it reads and writes no file.
      module NoBattery
        def self.load = nil

        def self.frame_ran = nil

        def self.close = nil
      end
    end
  end
end
