# 15 — Controllers

**Depends on:** 04

## Goal

Standard controllers on `$4016`/`$4017`, fed by a frontend-agnostic button state.

## Context

- Writing `$4016` bit 0 = 1 holds the shift registers in "strobe" (reloading continuously); writing 0 latches the
  buttons.
- Each read of `$4016` (port 1) or `$4017` (port 2) returns the next bit in bit 0, in order: A, B, Select, Start, Up,
  Down, Left, Right. After 8 reads an official controller returns 1. While strobe is high, every read returns A.
- The upper bits come from open bus (commonly `$40` from the address high byte).
- `$4017` writes go to the APU frame counter, not to the controller.

## Scope

In: `Input::Controller` (button bitmask set by the frontend, shift register), wiring both ports on the CPU bus, open
bus upper bits.

Out: Zapper, Four Score, DPCM read conflicts (backlog).

## Open decisions

- Allow Up+Down / Left+Right at the same time? Real controllers cannot; some games glitch. Recommendation: the
  frontend filters opposite directions by default, the core does not.

## Tasks

- [ ] Specify and test strobe high, latch, the 8-read sequence, reads after the 8th, independent ports, upper bits.

## Acceptance criteria

- [ ] Each button maps to its documented position.
- [ ] Reads beyond the 8th return 1 in bit 0.
- [ ] Strobe high returns the A state on every read.
- [ ] 100% branch coverage; rubocop clean.

## References

- Standard controller — https://www.nesdev.org/wiki/Standard_controller
- Controller reading — https://www.nesdev.org/wiki/Controller_reading
- Input devices — https://www.nesdev.org/wiki/Input_devices
