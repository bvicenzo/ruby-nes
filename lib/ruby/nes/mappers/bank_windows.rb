# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      # The windows through which a board shows one memory, PRG ROM to the CPU or CHR to the PPU: `window_count`
      # windows of `window_size` bytes from `first_address`, each an offset into the memory (`offsets`, which the board
      # reads on the hot path). A board selects a bank of any whole number of windows (`select`): MMC3's 8 KiB PRG and
      # 1 KiB or 2 KiB CHR banks (https://www.nesdev.org/wiki/MMC3), the 16 KiB of UxROM and MMC1, AxROM's 32 KiB.
      #
      # A bank past the end of the memory wraps around it, one window-sized piece at a time: a convention (plan 19,
      # decision 5) that matches a board whose memory lacks the upper address lines when its size is a power of two, as
      # on every licensed board, and that keeps the pieces of a memory that is not (80 KiB cpu_interrupts.nes, plan 20,
      # decision 9) inside it. Selection happens on register writes, off the hot path.
      class BankWindows
        attr_reader :offsets

        def initialize(memory_size:, window_size:, window_count:, first_address:)
          @memory_size = memory_size
          @window_size = window_size
          @first_address = first_address
          @piece_count = memory_size / window_size
          @offsets = Array.new(window_count, 0)
        end

        # Shows bank `bank`, counted in banks of `size` bytes, in the window at `address` and the windows after it
        # that the bank covers.
        def select(address, bank, size)
          windows_per_bank = size / @window_size
          first_window = (address - @first_address) / @window_size
          windows_per_bank.times do |index|
            piece = ((bank * windows_per_bank) + index) % @piece_count
            @offsets[first_window + index] = piece * @window_size
          end
        end

        # The number of the last bank of `size` bytes that starts in the memory.
        def last_bank(size) = @memory_size.ceildiv(size) - 1
      end
    end
  end
end
