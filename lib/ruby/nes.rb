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
require_relative 'nes/cpu'
