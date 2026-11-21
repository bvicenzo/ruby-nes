# frozen_string_literal: true

require_relative 'nes/version'

module Ruby
  # Nintendo Entertainment System emulator.
  module Nes
    class Error < StandardError; end
  end
end

require_relative 'nes/bits'
require_relative 'nes/cartridge'
require_relative 'nes/mappers'
require_relative 'nes/cpu_bus'
require_relative 'nes/ppu_bus'
require_relative 'nes/ppu'
require_relative 'nes/apu'
require_relative 'nes/cpu'
require_relative 'nes/input/controller'
require_relative 'nes/input/controller_ports'
require_relative 'nes/console'
require_relative 'nes/debug/tracer'
