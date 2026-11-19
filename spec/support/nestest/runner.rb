# frozen_string_literal: true

module Nestest
  # Runs a console step by step against expected trace lines (plan 08), the PPU along with the CPU (plan 12). Built by
  # `automation_mode` for nestest itself, or with any console for synthetic programs.
  class Runner
    # Automation mode: "set PC = $C000 instead of the reset vector" and nestest runs every test without a PPU
    # (https://www.nesdev.org/wiki/Emulator_tests).
    AUTOMATION_START = 0xC000
    # Where nestest writes the official and the unofficial opcodes' results: zero when every test passed
    # (other/nestest.txt).
    OFFICIAL_RESULT_ADDRESS = 0x0002
    UNOFFICIAL_RESULT_ADDRESS = 0x0003

    attr_reader :console

    # A powered-up console (Ruby::Nes::Console.new: the CPU's and the PPU's reset) with the program counter at $C000.
    def self.automation_mode(cartridge)
      console = Ruby::Nes::Console.new(cartridge)
      console.cpu.program_counter = AUTOMATION_START
      new(console:)
    end

    def initialize(console:)
      @console = console
      @tracer = Ruby::Nes::Debug::Tracer.new(cpu: console.cpu, bus: console.cpu_bus, ppu: console.ppu)
    end

    # The console's CPU, which the CPU benchmark steps alone.
    def cpu = @console.cpu

    # Compares the trace with each expected line in order, stepping the console after each match. Returns the first
    # Divergence, with the console left before that step, or nil once every line matched and the last step ran.
    def first_divergence(expected_lines)
      expected_lines.each.with_index(1) do |expected, line_number|
        actual = @tracer.line
        return Divergence.new(line_number:, expected:, actual:) unless actual == expected

        @console.step
      end
      nil
    end

    def official_result = @console.cpu_bus.read(OFFICIAL_RESULT_ADDRESS)

    def unofficial_result = @console.cpu_bus.read(UNOFFICIAL_RESULT_ADDRESS)
  end
end
