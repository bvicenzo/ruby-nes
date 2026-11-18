# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      # The processor status register P (https://www.nesdev.org/wiki/Status_flags), bits 7-0 `NV1B DIZC`. Six flags
      # are stored; bit 4 (B) and bit 5 have "No CPU effect" and exist only in the copy pushed to the stack. The
      # decimal flag does nothing on the 2A03 but "still exists and can be observed and modified, as normal".
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
          @flags = 0
        end

        def carry? = @flags.anybits?(CARRY_FLAG)

        def zero? = @flags.anybits?(ZERO_FLAG)

        def interrupt_disable? = @flags.anybits?(INTERRUPT_DISABLE_FLAG)

        def decimal? = @flags.anybits?(DECIMAL_FLAG)

        def overflow? = @flags.anybits?(OVERFLOW_FLAG)

        def negative? = @flags.anybits?(NEGATIVE_FLAG)

        def carry=(enabled)
          assign(CARRY_FLAG, enabled)
        end

        def zero=(enabled)
          assign(ZERO_FLAG, enabled)
        end

        def interrupt_disable=(enabled)
          assign(INTERRUPT_DISABLE_FLAG, enabled)
        end

        def decimal=(enabled)
          assign(DECIMAL_FLAG, enabled)
        end

        def overflow=(enabled)
          assign(OVERFLOW_FLAG, enabled)
        end

        def negative=(enabled)
          assign(NEGATIVE_FLAG, enabled)
        end

        # Zero when the byte is 0, negative when its bit 7 is set; the other flags stay as they are.
        def update_zero_and_negative(value)
          assign(ZERO_FLAG, value.zero?)
          assign(NEGATIVE_FLAG, value.anybits?(NEGATIVE_FLAG))
        end

        # The byte PHP and BRK push: B and bit 5 set.
        def byte_pushed_by_instruction
          @flags | NO_CPU_EFFECT_BITS # glossary: set-flag
        end

        # The byte NMI and IRQ push: bit 5 set, B clear. Also the form nestest's trace log shows.
        def byte_pushed_by_interrupt
          @flags | UNUSED_FLAG # glossary: set-flag
        end

        # PLP and RTI: the six flags take the byte's bits; B and bit 5 are dropped.
        def restore(byte)
          @flags = byte & ~NO_CPU_EFFECT_BITS # glossary: clear-flag
        end

        private

        def assign(flag, enabled)
          @flags = enabled ? @flags | flag : @flags & ~flag # glossary: set-flag, clear-flag
        end
      end
    end
  end
end
