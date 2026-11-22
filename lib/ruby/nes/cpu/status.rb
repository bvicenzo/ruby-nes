# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      # The processor status register P (https://www.nesdev.org/wiki/Status_flags), bits 7-0 `NV1B DIZC`. Six flags
      # are stored; bit 4 (B) and bit 5 have "No CPU effect" and exist only in the copy pushed to the stack. The
      # decimal flag does nothing on the 2A03 but "still exists and can be observed and modified, as normal".
      #
      # Each flag is a boolean ivar: instructions read and set flags far more often than the byte is pushed or pulled,
      # and plan 10 measured this representation 5% faster than one Integer with bit masks under YJIT (7% without a
      # JIT). The byte is composed only for PHP, BRK, interrupts and the trace, and split only by PLP and RTI.
      #
      # Callers are the CPU's own instructions, so values are trusted: setters take a boolean, `restore` and
      # `update_zero_and_negative` take a byte (0-255). Nothing is checked on this hot path. Bit 5 is not stored: both
      # pushed forms force it to 1.
      class Status
        CARRY_FLAG = 0x01
        ZERO_FLAG = 0x02
        INTERRUPT_DISABLE_FLAG = 0x04
        DECIMAL_FLAG = 0x08
        # "B is 0 when pushed by interrupts (NMI and IRQ) and 1 when pushed by instructions (BRK and PHP)".
        BREAK_FLAG = 0x10
        # Bit 5: "always pushed as 1".
        UNUSED_FLAG = 0x20
        OVERFLOW_FLAG = 0x40
        NEGATIVE_FLAG = Bits::SIGN_BIT
        # "The two bits with no CPU effect are ignored when pulling flags from the stack".
        NO_CPU_EFFECT_BITS = BREAK_FLAG | UNUSED_FLAG

        def initialize
          @carry = false
          @zero = false
          @interrupt_disable = false
          @decimal = false
          @overflow = false
          @negative = false
        end

        def carry? = @carry

        def zero? = @zero

        def interrupt_disable? = @interrupt_disable

        def decimal? = @decimal

        def overflow? = @overflow

        def negative? = @negative

        attr_writer :carry, :zero, :interrupt_disable, :decimal, :overflow, :negative

        # Zero when the byte is 0, negative when its bit 7 is set; the other flags stay as they are.
        def update_zero_and_negative(value)
          @zero = value.zero?
          @negative = (value & NEGATIVE_FLAG) != 0 # glossary: flag-set
        end

        # The byte PHP and BRK push: B and bit 5 set.
        def byte_pushed_by_instruction
          flags_byte | NO_CPU_EFFECT_BITS # glossary: set-flag
        end

        # The byte NMI and IRQ push: bit 5 set, B clear. Also the form nestest's trace log shows.
        def byte_pushed_by_interrupt
          flags_byte | UNUSED_FLAG # glossary: set-flag
        end

        # PLP and RTI: the six flags take the byte's bits; B and bit 5 are dropped.
        def restore(byte)
          @carry = (byte & CARRY_FLAG) != 0 # glossary: flag-set
          @zero = (byte & ZERO_FLAG) != 0 # glossary: flag-set
          @interrupt_disable = (byte & INTERRUPT_DISABLE_FLAG) != 0 # glossary: flag-set
          @decimal = (byte & DECIMAL_FLAG) != 0 # glossary: flag-set
          @overflow = (byte & OVERFLOW_FLAG) != 0 # glossary: flag-set
          @negative = (byte & NEGATIVE_FLAG) != 0 # glossary: flag-set
        end

        private

        # The six stored flags at their bit positions.
        def flags_byte
          (@carry ? CARRY_FLAG : 0) | # glossary: set-flag
            (@zero ? ZERO_FLAG : 0) | # glossary: set-flag
            (@interrupt_disable ? INTERRUPT_DISABLE_FLAG : 0) | # glossary: set-flag
            (@decimal ? DECIMAL_FLAG : 0) | # glossary: set-flag
            (@overflow ? OVERFLOW_FLAG : 0) | # glossary: set-flag
            (@negative ? NEGATIVE_FLAG : 0) # glossary: set-flag
        end
      end
    end
  end
end
