# frozen_string_literal: true

module Blargg
  # What a ROM built with blargg's older shell (cpu_dummy_reads) reports. It writes nothing at $6000: its text console
  # draws on nametable 0 with tiles whose numbers are ASCII codes (console.s fills the nametable with $20, the space),
  # and the program ends with a line "Passed", "Failed" or "Error <code>" (shell.inc's exit, testing.s's
  # tests_passed), then loops forever. A line only reaches the nametable whole, when its newline flushes it, so a
  # result line on screen means the run is over. Same interface as Report, for Runner; read through the console's PPU
  # bus, with no side effect.
  class ScreenReport
    # The suites of the manifest that report this way.
    SUITES = %w[cpu_dummy_reads/].freeze
    # Nametable 0: 30 rows of 32 tiles (https://www.nesdev.org/wiki/PPU_nametables).
    NAMETABLE_START = 0x2000
    COLUMNS = 32
    ROWS = 30
    PASSED_LINE = 'Passed'
    FAILED_LINE = 'Failed'
    ERROR_LINE = /\AError (?<code>\d+)\z/
    PASSED = 0
    FAILED = 1

    def initialize(console)
      @ppu_bus = console.ppu_bus
    end

    # :running or :finished.
    def state = code ? :finished : :running

    # 0 for passed, 1 for failed, the code of an error; nil until a result is on screen.
    def code
      lines.each do |line|
        return PASSED if line == PASSED_LINE
        return FAILED if line == FAILED_LINE

        error = ERROR_LINE.match(line)
        return Integer(error[:code], 10) if error
      end
      nil
    end

    # The rows with text, without their margins, one per line.
    def text = lines.join("\n")

    private

    def lines = Array.new(ROWS) { |row| row_text(row) }.reject(&:empty?)

    # Strips the console's spaces and the zero tiles of a nametable nothing drew on.
    def row_text(row)
      row_start = NAMETABLE_START + (row * COLUMNS)
      Array.new(COLUMNS) { |column| @ppu_bus.read(row_start + column) }.pack('C*').strip
    end
  end
end
