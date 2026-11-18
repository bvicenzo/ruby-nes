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
