# 15 — Controllers

**Status:** done (2026-11-19)

**Depends on:** 04

## Goal

Standard controllers on `$4016`/`$4017`, fed by a frontend-agnostic button state.

## Context

From [Standard controller](https://www.nesdev.org/wiki/Standard_controller) and
[Controller reading](https://www.nesdev.org/wiki/Controller_reading):

- Bit 0 of a `$4016` write is the strobe. "Writing 1 to $4016 causes the register to fill its parallel inputs from the
  buttons currently held"; while it is high, reads "will keep returning the current state of the first button (A)".
  "Once S goes low, this reloading will stop", so the buttons are latched as the strobe falls; "a 1/0 write sequence
  is required to get the button states". "Other bits are ignored" (bits 2-1 are the expansion port latches, out of
  scope).
- "Though both are polled from a write to $4016, controller 1 is read through $4016": one write strobes both ports.
  "$4016 reads only from controller port 1, and $4017 reads only from controller port 2", so each read clocks only its
  own port.
- Each read returns the next button in bit 0, in the order "A, B, Select, Start, Up, Down, Left, Right", "1 if pressed,
  0 if not pressed". "All subsequent reads will return 1 on official Nintendo brand controllers".

From [Open bus behavior](https://www.nesdev.org/wiki/Open_bus_behavior): "The controller ports ($4016, $4017) affect
only bits 4-0"; "Bits 7-5 repeat the corresponding bits from the previous read, usually 010 from the high byte $40".
The standard controller drives D0 only, and on the NES-001 D4-D1 read "0 if not connected"
([Controller reading](https://www.nesdev.org/wiki/Controller_reading), table of unconnected data lines). Plan 04's
devices get the data bus value in `cpu_read(address, data_bus)` and return what is left on the bus, so the ports keep
bits 7-5 of `data_bus` and drive bits 4-0.

From [DMA](https://www.nesdev.org/wiki/DMA): the 2A03 decodes its registers from "bits 4-0 from the 2A03 address bus
and bits 15-5 from the 6502 core", and "The 6502 core keeps the same address while halted". Halted on the opcode fetch
after the `$4014` write, the core is never in `$4000-$401F`, so an OAM DMA from page `$40` reaches no 2A03 register
and never clocks the controllers (found by the code review; decision 7).

`$4017` writes go to the APU frame counter (plan 22), not to the controllers.

## Scope

In: `Input::Controller` (button bitmask set by the frontend, strobe, shift register), `Input::ControllerPorts` (the
device answering `$4016`/`$4017`, open bus bits 7-5), the `CpuBus` slot split, the `Console` wiring and
`Console#controllers` for frontends.

Out: Zapper, Four Score, DPCM read conflicts (backlog), the expansion port latches (bits 2-1 of `$4016` writes),
third-party controllers that "may return 0" after the 8th read.

## Decisions

Settled with the user on 2026-11-19.

1. **The `$4000-$4017` slot is split in `CpuBus`.** A new `controller_ports:` slot receives reads of `$4016`/`$4017`
   and writes to `$4016`; the remaining slot is renamed `apu_registers:` (`$4000-$4015`, writes to `$4017`; reads of
   `$4014` still reach it). Reason: it mirrors the 2A03's own decoding (the ports leave the chip through /OE1, /OE2
   and OUT0-2, the APU is internal), as `$4014` already does; `$4016`/`$4017` are the last two addresses before
   `$4018`, so reads gain one `elsif` and writes one equality, with no intermediate object on the hot path. A
   composite device in a single slot was discarded: one more hop per access and a routing decision outside the bus.
2. **Opposite directions are not filtered by the core**; the frontend filters them by default (plan 18). NESdev says
   nothing about it: a project decision.
3. **A second write of 0 while the strobe is already low does nothing**: the read sequence does not restart. Reason:
   "Once S goes low, this reloading will stop"; nothing reloads the register while the strobe stays low.
4. **Official controllers only**: reads after the 8th return 1.
5. **Initial state**: shift register 0 and strobe low. Not documented; no spec leaf rests on it.
6. **Frontend interface**: `Console.new(cartridge, controllers:)` takes the two controllers (two released ones by
   default; specs inject them already holding their buttons, as `Vicenzo/RSpec/MutatedPremises` asks) and
   `Console#controllers` returns them (frozen); `Controller.new(buttons:)` sets the initial buttons and
   `Controller#buttons=` takes a
   bitmask in report order (bit 0 = A … bit 7 = Right); `Controller::BUTTONS` is a frozen table from button name to
   bit (`{ a: 0x01, b: 0x02, select: 0x04, start: 0x08, up: 0x10, down: 0x20, left: 0x40, right: 0x80 }`), ready for
   plan 16's input script (`120: [start]`).

7. **OAM DMA reads go through `CpuBus#read_for_dma`**, where `$4000-$401F` is open bus (the data bus value, no device
   reached); every other address reads as `CpuBus#read`. Reason: the DMA page above; without it a DMA from page `$40`
   would clock both controllers (and, from plan 22, read `$4015` with its side effects). `FlatBus` answers it with a
   plain read.

## What was done

- `Input::Controller`: buttons held as a mask in report order (`BUTTONS`, `Controller.new(buttons:)`, `buttons=`),
  strobe on bit 0 of the `$4016` write with continuous reload while high and the latch as it falls, reads in the order
  A … Right, then 1.
- `Input::ControllerPorts`: `$4016` reads the first controller and `$4017` the second, bits 7-5 from the data bus and
  4-1 zero; a `$4016` write strobes both.
- `CpuBus`: the `io_registers:` slot split into `apu_registers:` and `controller_ports:` (decision 1);
  `read_for_dma`, through which OAM DMA reads `$4000-$401F` as open bus (decision 7). The CPU benchmark variants that
  reopen `CpuBus` follow the split.
- `Console.new(cartridge, controllers:)` and `Console#controllers`, with an end-to-end program reading `$41` with A held
  on the first controller.
- `docs/architecture.md`: the slots, a Controllers section, decision 35 and the DMC conflict in Known gaps;
  `docs/GLOSSARY.md`: I/O. Plans 16, 18 and 22 aligned.
- 42 new examples, full branch coverage of every touched unit; one independent code review. Review follow-ups applied:
  the OAM DMA read path (decision 7, checked against the DMA page), specs of `Console#controllers` and a copy of the
  given array, decision 20's wording, `SECOND_PORT`, the open bus mask named like the PPU's, two citations moved to
  Standard controller, the "0 if not connected" source for D4-D1. Not applied: one tree for the open bus merge of both
  ports (each port is its own path), validating the number of controllers (our own frontend passes them).

## Tasks

- [x] Specify and test `Input::Controller`: each button at its documented position, reads after the 8th, strobe high
      returning the current A on every read, buttons changed after the latch not affecting the reads, a second write of
      0 not restarting the sequence, bits 7-1 of the write ignored.
- [x] Specify and test `Input::ControllerPorts`: `$4016` reads the first controller and `$4017` the second, bits 7-5
      from the data bus and 4-1 zero, a read of one port not clocking the other, a write strobing both.
- [x] Split the `CpuBus` slot (`apu_registers:`, `controller_ports:`) and specify the boundaries `$4015`/`$4016`, the
      `$4017` read (ports) and write (APU), the `$4016` write (ports, not APU).
- [x] Wire the console (`Console#controllers`), with an end-to-end case: a program strobing and reading `$4016` with A
      pressed stores `$41` (bit 0 = A, bits 7-5 = `010` from the operand's high byte `$40`); with A released, `$40`.
- [x] Update `docs/architecture.md` (slots, diagram, layout, decision log) and `docs/GLOSSARY.md` (I/O); align plans
      16, 18 and 22.

## Acceptance criteria

- [x] Each button maps to its documented position.
- [x] Reads beyond the 8th return 1 in bit 0.
- [x] Strobe high returns the A state on every read.
- [x] One write to `$4016` strobes both ports; each read clocks only its own port.
- [x] Bits 7-5 of a read come from open bus and bits 4-1 are 0; the end-to-end program reads `$41` with A pressed.
- [x] A write to `$4017` does not reach the controllers.
- [x] 100% branch coverage; rubocop clean; `SLOW=1 bundle exec rake` green.

## References

- Standard controller — https://www.nesdev.org/wiki/Standard_controller
- Controller reading — https://www.nesdev.org/wiki/Controller_reading
- Open bus behavior — https://www.nesdev.org/wiki/Open_bus_behavior
- Input devices — https://www.nesdev.org/wiki/Input_devices
