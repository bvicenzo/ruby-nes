# 21 — Mapper MMC3 and Super Mario Bros. 3

**Status:** done (2026-11-21)

**Depends on:** 14, 18, 20

## Goal

Mapper 4 (MMC3) with its scanline IRQ, and Super Mario Bros. 3 playable. Milestone M5.

## Context

From the MMC3 page (references below):

- "The MMC3 has 4 pairs of registers at $8000-$9FFF, $A000-$BFFF, $C000-$DFFF, and $E000-$FFFF": even addresses
  select the first register of each pair, odd ones the second. "All registers of MMC3 are write-only."

  | Address | Register |
  |---|---|
  | `$8000` even | bank select: R0–R7 (bits 2-0), PRG ROM bank mode (bit 6), CHR A12 inversion (bit 7) |
  | `$8001` odd | bank data for the selected register |
  | `$A000` even | nametable arrangement: 0 horizontal, 1 vertical; "no effect on cartridges with hardwired 4-screen VRAM" |
  | `$A001` odd | PRG RAM protect: bit 7 chip enable, bit 6 write deny |
  | `$C000` even | IRQ latch, "the IRQ counter reload value"; "does not immediately affect the value within the counter" |
  | `$C001` odd | IRQ reload: "clears the MMC3 IRQ counter immediately", reloaded on the next rising A12 edge |
  | `$E000` even | "disable MMC3 interrupts AND acknowledge any pending interrupts"; the counter keeps running |
  | `$E001` odd | "enable MMC3 interrupts" |

- **PRG** in 8 KiB banks: mode 0 shows R6, R7, the second-last bank and the last bank at `$8000`, `$A000`, `$C000`,
  `$E000`; mode 1 swaps `$8000` and `$C000`. "R6 and R7 will ignore the top two bits, as the MMC3 has only 6 PRG ROM
  address lines." R6, R7 and `$8000` "are unspecified at power on", so the reset vector lies in the fixed last bank.
- **CHR**: R0 and R1 are 2 KiB banks, R2-R5 1 KiB banks; without inversion the 2 KiB banks are at `$0000-$0FFF` and
  the 1 KiB ones at `$1000-$1FFF`, with inversion the other way round. "2 KB banks can only select even numbered CHR
  banks. (The lowest bit is ignored.)"
- **IRQ counter**: clocked on a rising edge of PPU A12 "after the line has remained low for three falling edges of
  M2". On a clock: if the counter is 0 or a reload was requested, it loads the latch, otherwise it decrements; if it is
  0 after that and IRQs are enabled, the IRQ is asserted. "No matter what caused it": with background at `$0000` and
  sprites at `$1000` it happens once per scanline around dot 260, and it is "possible to (intentionally or not) clock
  the counter by writing to $2006". With latch 0, Sharp MMC3B/C ("new", submapper 0) "generate an IRQ on each scanline
  while $C000 is $00"; Sharp MMC3A and NEC ("old"/"alternate", submapper 4) only when the counter becomes 0 from a
  non-zero value.
- **`mmc3_test_2`** (readme): ROMs 1-4 "mainly clock the IRQ counter by writing $2006"; "The last two ROMs test behavior
  that differs among MMC3 chips"; the IRQ flag is not set when `$C001` clears the counter. Output at `$6000`, as the
  other blargg suites. The readme believes SMB3 has revision B.
- `Mappers::Base` (plan 19, decision 1) reads PRG through two 16 KiB windows and CHR through two 4 KiB windows (plan
  20, decision 5); MMC3 needs 8 KiB PRG windows and 1 KiB CHR windows.
- Only pattern fetches and `$2007` accesses reach the board (`ppu_read`/`ppu_write`); a `$2006` write reaches nothing.
- The IRQ line is still `Cpu#irq_line=` and the boards' `irq?` (architecture decision 25 is not implemented).
- SMB3 (from plan 03): mapper 4, 256 KiB PRG, 128 KiB CHR, 8 KiB PRG-RAM at `$6000` (no battery). It uses the IRQ to
  split the screen between the playfield and the status bar; wrong IRQ timing shows up as a shaking or torn status bar.

## Scope

In: MMC3 banking, mirroring (four-screen from the header), PRG RAM, the IRQ counter driven by A12 from the PPU's
pattern fetch addresses and PPUADDR writes, the wired-OR IRQ line, the PPU caught up before mapper register writes.

Out: MMC6 specifics, `$A001` (decision 4), the "old" revision, the battery (SMB3 has none), the garbage nametable
fetches of dots 257-320 (decision 9).

## Decisions

Settled with the user on 2026-11-21.

1. **A12 source: the board watches every address the PPU puts on its bus that reaches it.** MMC3 watches A12 in
   `ppu_read`/`ppu_write` (pattern fetches, `$2007` accesses) and in a new mapper hook, `ppu_address(address)` (a no-op
   in the base), which the PPU calls with v after each PPUADDR write (the first leaves v unchanged, so only the second
   can raise A12) and after each PPUDATA increment, outside rendering (decision 10); `3-A12_clocking`'s source showed
   the increment matters. The "scanline at dot 260" shortcut stays documented as a fallback. The
   hook's cost is measured with headless frames.
2. **The filter's clock is the PPU.** Every board gets the PPU as it gets the CPU (`ppu=`, wired by `Console`);
   `Ppu#elapsed_dots` (dots since power-up) / 3 counts M2 cycles, and a rise clocks the counter when A12 stayed low
   for at least 3 of them. `@cpu.cycles` cannot serve: during the PPU's catch-up it is already the end of the
   instruction.
3. **Revision "new" (Sharp MMC3B/C, submapper 0).** The ROM of the other revision is recorded with its result.
4. **`$A001` is ignored; PRG RAM is 8 KiB, always enabled.** "Many emulators choose not to implement them as part of
   iNES Mapper 004 to avoid an incompatibility with the MMC6".
5. **The IRQ line is a wired-OR of sources.** `Cpu#assert_irq(source)` and `Cpu#release_irq(source)`, one bit per
   source in `Cpu::InterruptLines` (the mapper's now; plan 22 adds the frame counter, plan 23 the DMC); an IRQ is
   pending while any source asserts it and I is clear. `Cpu#irq_line=` and `Mappers::Base#irq?` go away.
6. **The base catches the PPU up before every register write** (`$8000-$FFFF`): to `cpu.cycles - 1`, as
   `Console::PpuRegisterSync`, then `write_register`. Only on the write path (rare); every board benefits, and the
   Known gap "Mapper register timing" closes.
7. **Four-screen comes from the header in the base**: `alternative_nametables` makes the base's mirroring
   `:four_screen` (iNES flags 6 bit 3 is board-independent); MMC3 ignores `$A000` then. Boards that control their own
   mirroring, AxROM and MMC1, set theirs over it, as their hardware does (narrowed after the review: no four-screen
   AxROM or MMC1 board is known).
8. **The base's windows become 4 × 8 KiB of PRG and 8 × 1 KiB of CHR**, selected by one generic helper (a bank of N
   windows from window W, wrapped by the number of banks of that size); the current helpers become thin calls on it
   and UxROM, CNROM, AxROM and MMC1 keep their behaviour. Measured with headless frames, recorded in
   `docs/benchmarks.md`: every frame reads PRG on each instruction and CHR on each fetch, so they cover both windows
   (amended after the review; `rake bench:cpu` was not run).
9. **The garbage nametable fetches of dots 257-320 stay unmade.** Nametable addresses have A12 = 0 and the lows between
   sprite fetches are shorter than the filter, so MMC3 does not need them; the Known gaps row is updated.
10. **v is shown on the PPU bus only outside rendering**, after a PPUADDR write and after each PPUDATA increment
    (`DataPort#show_address` → `PpuBus#place_address` → the board's `ppu_address`). Added during the work: the source of
    `3-A12_clocking` clocks the counter with a PPUDATA read and write taking v from `$0FFF` to `$1000`. During
    rendering nothing is shown, a deliberate divergence from the MMC3 page, which says the counter can be clocked "by
    writing to $2006 regardless of whether PPU is/is not rendering": there v's bit 12 is fine Y, showing it would clock
    SMB3's counter falsely, and the board already sees every rendering fetch, which uses v.
11. **MMC3's mirroring is the header's until `$A000` is written**, an exception to "every register starts at 0" (plan
    19, decision 6): `$A000` bit 0 clear is CIRAM A10 on PPU A10, vertical mirroring, bit 0 set horizontal.
12. **`mmc3_test_2`'s revision ROMs:** `5-MMC3` tests the "new" behaviour and passes; `6-MMC3_alt` the old one
    ("My copy of Crystalis in particular behaves this way, but not my copy of Super Mario Bros. 3") and fails #2, as
    expected. `4-scanline_timing` fails #2, the IRQ early on scanline 0 (Known gaps: MMC3 IRQ timing, plan 22).
13. **A12 starts low, low since dot 0**, so the first rise 3 M2 cycles after power-up clocks the counter: a convention,
    no page found says what the PPU's bus holds at power-up (added after the review).
14. **The reload flag of the wiki's model is not kept**: `$C001` clears the counter, and a counter at 0 loads the latch
    on the next clock anyway, so in the "new" behaviour the flag changes nothing (after the review).

## Tasks

- [x] Specify and test the wired-OR IRQ line (`Cpu::InterruptLines`, `Cpu`); remove `irq_line=` and `Base#irq?`.
- [x] Specify and test the base's 8 KiB / 1 KiB windows and the generic bank helper (`Mappers::BankWindows`); adapt
      the boards; measure.
- [x] Specify and test the base's `ppu=`, the PPU catch-up before register writes, `ppu_address` and four-screen.
- [x] Specify and test `Ppu#elapsed_dots` and the PPUADDR write reaching the board's `ppu_address`.
- [x] Specify and test `Mappers::Mmc3::IrqCounter`: reload, decrement, zero with IRQ enabled/disabled, acknowledge,
      latch = 0, `$C001` without IRQ.
- [x] Specify and test `Mappers::Mmc3::A12Watcher`: a filtered rise clocks the counter, a short low does not, falling
      or unchanged A12 does not.
- [x] Specify and test `Mappers::Mmc3`: bank select/data for every register and both modes (PRG mode, CHR inversion),
      mirroring, PRG RAM, the A12 feed.
- [x] Register it in `Mappers.build`; wire the PPU into the board in `Console`.
- [x] Add `mmc3_test_2` to the manifest; passing ROMs become slow examples of `Blargg::Runner#run`.
- [x] Play SMB3 with the scripted headless input first (title → world map → 1-1; a `local_rom:` slow example of
      `Console#run_frame` checking the status bar).
- [x] Play SMB3 interactively (the user, in the window).
- [x] Update `docs/architecture.md`, `docs/GLOSSARY.md`, `docs/test-roms.md`, `docs/benchmarks.md`; align plan 22.

## Acceptance criteria

- [x] `mmc3_test_2` ROMs `1-clocking`, `2-details`, `3-A12_clocking` and the revision ROM matching the "new" behaviour
      pass; `4-scanline_timing` and the other revision ROM are recorded with their result and reason.
- [x] SMB3 boots to the title screen, the world map, and world 1-1.
- [x] The status bar stays still while the playfield scrolls (checked by a spec comparing the status bar's pixels over
      several frames during scrolling and headless screenshots, then by play).
- [x] World 1-1 can be finished by playing interactively.
- [x] The cost of the windows and of the A12 hook is measured and recorded.
- [x] 100% branch coverage on MMC3 and the units touched; rubocop clean; `SLOW=1 bundle exec rake` green (the windowed
      backend specs excluded in the session, which has no display; they are unchanged).

## What was done

- The IRQ line is wired-OR: `Cpu#assert_irq`/`Cpu#release_irq`, one bit per source (`Cpu::InterruptLines::MAPPER_IRQ`);
  `Cpu#irq_line=` and `Base#irq?` are gone.
- `Mappers::BankWindows`: the base shows PRG through four 8 KiB windows and CHR through eight 1 KiB windows, a bank
  being a whole number of windows; UxROM, CNROM, AxROM and MMC1 use `select_prg_bank`/`select_chr_bank`. About 3% of
  headless frames under YJIT and ZJIT (`docs/benchmarks.md`).
- `Mappers::Base`: the PPU catches up before a register write (`PpuRegisterSync#catch_up`), `ppu=` and
  `register_sync=` wired by `Console`, `ppu_address` (a no-op), four-screen from the header.
- `Ppu#elapsed_dots`; v reaches the board's `ppu_address` after PPUADDR writes and PPUDATA increments, outside
  rendering only (decision 12).
- `Mappers::Mmc3` (mapper 4) with `Mmc3::IrqCounter` (the "new" Sharp MMC3B/C behaviour) and `Mmc3::A12Watcher` (a
  rise after at least 3 M2 cycles low). The A12 watch is within noise under YJIT and costs 3-5% under ZJIT on SMB3.
- Test ROMs: `mmc3_test_2` 1-3 and 5 pass (slow examples); 4 fails test 2 (the IRQ polling gap, plan 22) and 6 fails
  test 2 (the old revision), as `docs/test-roms.md` records.
- SMB3: a `local_rom:` slow example plays into world 1-1 with a scripted input (`ScriptedPlay`, `FrameRegion`) and
  checks the status bar over 100 scrolling frames. The user finished 1-1 in the window: the status bar stays still
  through horizontal and vertical scrolling, the card is won and the map comes back, at 13-15 fps under YJIT (a
  starting point for plan 25). The backdrop-coloured strip on the left, beside the status bar too, is the game's own
  PPUMASK `$18`: both layers hidden in the leftmost 8 pixels (https://www.nesdev.org/wiki/PPU_registers#PPUMASK).
- `docs/architecture.md` (interrupt lines, mapper interface, board table, clock model, Known gaps, decisions 51-56),
  `docs/GLOSSARY.md` (A12, M2, MMC3, TxROM, R0-R7, KiB); plan 22 inherits the IRQ line.
- Independent review: the second PPUADDR write, the power-up A12 convention (decision 13) and the reload flag removed
  (decision 14), the divergence from the wiki's `$2006` note documented, four-screen's scope narrowed, `InputScript`
  and `Picture::WIDTH` reused, the exact IRQ count in `Console`'s example. Not applied: MMC3 without its wiring raises
  `NoMethodError` (documented), and the stale `bench/cpu_benchmark/variants/` (pre-existing).

## References

- MMC3 — https://www.nesdev.org/wiki/MMC3
- MMC3 IRQ and A12 — https://www.nesdev.org/wiki/MMC3#IRQ_Specifics
- TxROM board family — https://www.nesdev.org/wiki/TxROM
- iNES (flags 6 bit 3, four-screen) — https://www.nesdev.org/wiki/INES
- PPU rendering (when pattern fetches happen) — https://www.nesdev.org/wiki/PPU_rendering
- `mmc3_test_2` — https://github.com/christopherpow/nes-test-roms (`mmc3_test_2/readme.txt`, `mmc3_test_2/source/`)
- `mmc3_irq_tests` readme (failure codes of the older build) — same collection
