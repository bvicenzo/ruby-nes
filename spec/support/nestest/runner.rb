# frozen_string_literal: true

module Nestest
  # Runs a CPU instruction by instruction against expected trace lines (plan 08). Built by `automation_mode` for
  # nestest itself, or with any CPU and bus for synthetic programs.
  class Runner
    # Automation mode: "set PC = $C000 instead of the reset vector" and nestest runs every test without a PPU
    # (https://www.nesdev.org/wiki/Emulator_tests).
    AUTOMATION_START = 0xC000
    # Where nestest writes the official opcodes' result: zero when every test passed (other/nestest.txt).
    OFFICIAL_RESULT_ADDRESS = 0x0002

    attr_reader :cpu

    # A powered-up console (Cpu.new followed by reset: https://www.nesdev.org/wiki/CPU_power_up_state) with the
    # cartridge's board on the CPU bus and the program counter at $C000.
    def self.automation_mode(cartridge)
      bus = Ruby::Nes::CpuBus.new(mapper: Ruby::Nes::Mappers.build(cartridge))
      cpu = Ruby::Nes::Cpu.new(bus:)
      cpu.reset
      cpu.program_counter = AUTOMATION_START
      new(cpu:, bus:)
    end

    def initialize(cpu:, bus:)
      @cpu = cpu
      @bus = bus
      @tracer = Ruby::Nes::Debug::Tracer.new(cpu:, bus:)
    end

    # Compares the trace with each expected line in order, running the instruction after each match. Returns the
    # first Divergence, with the CPU left before that instruction, or nil once every line matched and the last
    # instruction ran.
    def first_divergence(expected_lines)
      expected_lines.each.with_index(1) do |expected, line_number|
        actual = @tracer.line
        return Divergence.new(line_number:, expected:, actual:) unless actual == expected

        @cpu.step
      end
      nil
    end

    def official_result = @bus.read(OFFICIAL_RESULT_ADDRESS)
  end
end
