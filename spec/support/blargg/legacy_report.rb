# frozen_string_literal: true

module Blargg
  # What a 2005 blargg ROM (sprite_hit_tests_2005.10.05, sprite_overflow_tests) reports. They show their result "on
  # screen and by beeping"; their source (validation.a, runtime_rom.a) keeps it in `result = $f8`, 1 for passed and the
  # failing test's number otherwise (0 an internal error), and ends in `exit: jmp exit`, an absolute JMP to itself. The
  # state is read from the CPU: :finished once PC is on that loop in PRG ROM, :running before; the bus is read only
  # there, where reads have no side effect. Same interface as Report, for Runner.
  class LegacyReport
    # The suites of the manifest that report this way.
    SUITES = %w[sprite_hit_tests_2005.10.05/ sprite_overflow_tests/].freeze
    RESULT_ADDRESS = 0x00F8
    # The cartridge's PRG ROM on the CPU bus (https://www.nesdev.org/wiki/CPU_memory_map).
    PRG_ROM_START = 0x8000
    JUMP_ABSOLUTE = 0x4C
    PASSED = 0x01

    def initialize(console)
      @cpu = console.cpu
      @bus = console.cpu_bus
    end

    # :running or :finished.
    def state = looping_on_itself? ? :finished : :running

    def code = @bus.read(RESULT_ADDRESS)

    # The text is only on screen.
    def text = ''

    private

    def looping_on_itself?
      program_counter = @cpu.program_counter
      return false if program_counter < PRG_ROM_START
      return false unless @bus.read(program_counter) == JUMP_ABSOLUTE

      low = @bus.read(Ruby::Nes::Bits.wrap_to_word(program_counter + 1))
      high = @bus.read(Ruby::Nes::Bits.wrap_to_word(program_counter + 2))
      Ruby::Nes::Bits.combine_bytes(low:, high:) == program_counter
    end
  end
end
