# 38 — Pause menu

**Status:** done (2026-11-26)

**Depends on:** 36 (gamepad input), 37 (the menu's look and the window's lifecycle)

## Goal

In a game, a pause menu over the paused picture gathers what today is a hotkey list: resume, save and load states
(choosing the slot by its picture), reset, back to the list, quit. It opens from the keyboard and from the gamepad
alone, so a game can be left, and the program quit, without the keyboard. The ROM list gets a small menu too.

The controls screen (rebinding keys and gamepad buttons on screen, writing the config file) was split off to plan 40
(decision 1).

## Context

- Controls live in `~/.config/ruby-nes/config.yml` (`keys:` since plan 18, `gamepad:` since plan 36), read once by
  `Frontends::KeyConfig`, each section through `KeyConfig::Section`'s rules: an action takes a list of inputs, `[]`
  leaves it without one, and an input the file gives to another action leaves its default action.
- Plan 37 brings the menu's look and a window that outlives a game. Its menu is an NES frame composed in Ruby
  (`Frontends::Browser::Screen`, with the 8×8 `Frontends::Browser::PixelFont`) and drawn like a game, navigated with
  controller 1's buttons (`Frontends::Players`, through `Browser::ButtonPresses` and `Browser::Cursor`). In a game
  started from its list, Escape (the hotkeys' `quit`) returns to the list (plan 37, decision 5); in the list it quits;
  `ruby-nes ROM` keeps Escape quitting. Returning to the list and quitting from the gamepad alone were left to this
  plan.
- Plan 35 brings ten save state slots per game (`Saves::StateSlots`, `Saves::StateFiles`), driven by F5-F8 through
  `Frontends::Driver`'s `state_action`; a state restores a console whose frame buffer is the picture of the moment
  (plan 37's previews show it).
- Plan 36 left hotkeys on the pad and the pad's way into this menu to this plan (decision 3). The pad's way in is
  here; hotkeys on the pad go to plan 40.
- Today `Frontends::Base#running?` false ends a screen (a game returns to the list) and `#closed?` ends the session
  (the window's close button). The menu needs both, on request.

## Scope

In:

1. **The pause menu**, over the game's picture dimmed (decision 4): RESUME, SAVE STATE, LOAD STATE, RESET, BACK TO THE
   LIST (only in a game started from the list), QUIT. Escape opens it, and L + R held together on the first gamepad
   (decision 3). In the menu, Escape, L + R or B close it (or go back a level), up and down move, A or Start choose.
2. **Save and load from the menu** through a slot picker: the ten slots, empty or written, the current one in focus,
   and the picture of the slot in focus at half size, read from its state (decision 4). Choosing a slot saves or loads
   there, makes it the current slot, shows `Saves::StateSlots`' message and resumes.
3. **Back to the game cleanly:** the controllers' buttons held as the menu closes are ignored until released, so the A
   that chose RESUME does not make Mario jump, nor a held Start pause the game.
4. **The list's menu:** Escape or L + R in the ROM list opens a menu over it: RESUME (back to the list) and QUIT.
5. **Keys:** a `menu` hotkey (Escape) in `keys:`; `quit` stays a hotkey, with no default key (decision 2).
6. README: the menus, their keys and buttons, `menu:` and `quit:` in the config file.

Out:

- The controls screen, writing the config file, hotkeys on the pad and a CONTROLS entry in both menus: plan 40.
- Video and audio settings on screen (scale, aspect, overscan, volume), as before: backlog.

## Decisions

Settled with the user on 2026-11-26:

1. **Split the plan.** The pause menu (this plan) and the controls screen (plan 40) are nearly independent and were
   about 19 units together. Plan 40 depends on this one and takes the original open decision 1 (writing the config
   file). Milestone M10 moves to plan 40.
2. **Escape opens a menu everywhere** (the original open decision 2, option (a)): it becomes the `menu` hotkey. In a
   game it opens the pause menu, which in `ruby-nes ROM` has no BACK TO THE LIST; in the list it opens the list's menu;
   in a menu it closes it. P keeps pausing silently. `quit` stays a hotkey with no default key, so a config file with
   `quit: escape` takes Escape back from `menu` by the file's rule and gives Escape its meaning before this plan (a
   game started from the list returns to it, elsewhere it quits).
   Why: one rule ("Escape goes up a level, through a menu") instead of three, and quitting at once was the riskier key.
3. **On the pad: L + R held together on gamepad 0** (raylib's `LEFT_TRIGGER_1` and `RIGHT_TRIGGER_1`, the user's
   SNES pad's L and R, plan 36's probe), fixed, as the window's close button is. It fires on the frame the second of
   the two becomes held, once until either is released. Why: NES games never see L or R, so it can't collide with a
   game; Select + Start could (many games soft-reset on A + B + Select + Start), and the guide button (`middle`) is
   missing on SNES pads. L and R alone stay free for plan 40's hotkeys on the pad.
4. **Look:** the paused game's picture dimmed, each colour of the NES palette replaced by the same hue one luminance
   row lower (a table of the 512 pixel values, emphasis bits kept; the blacks of columns $xD-$xF and the darkest row
   become black, https://www.nesdev.org/wiki/PPU_palettes), computed once as the menu opens, with the menu's box over
   it. A slot's picture is its state restored into a scratch console of the same cartridge and sample rate (about
   4 ms, as plan 37's previews), so it has exact palette indices; the PNG pictures beside the states stay for the
   person, with no PNG decoder. The picker's pictures are kept while it is open.

## Tasks

- [x] `Frontends::KeyConfig` and `Frontends::Hotkeys`: the `menu` hotkey (Escape), `quit` without a default key,
      `menu_requested?` for the frame its key is pressed, TDD.
- [x] `Frontends::MenuCombination` (L + R on gamepad 0, on the frame both become held), TDD.
- [x] `Frontends::HeldOver` (the buttons held as a menu closes, ignored until released), TDD.
- [x] `Frontends::Base` and `Frontends::Raylib`: `menu_requested?`, `leave` (ends the screen), `quit` (ends the
      session: `closed?`), `resume` (the hotkeys start over, held buttons ignored), TDD.
- [x] `Frontends::Screens`: `PixelFont`, `ButtonPresses` and `Cursor` moved out of `Browser`; `Screens::Canvas`
      extracted from `Browser::Screen` (text on the grid, centred, a filled area, a frame, a picture at half size), TDD.
- [x] `Screens::Shade` (the dimmed picture, decision 4), TDD.
- [x] `Screens::Choices` (a vertical list of entries: move, choose, back; unavailable entries), TDD.
- [x] `Pause::Screen` (the menu's box over the dimmed picture; the slot picker with the slot in focus's picture), TDD.
- [x] Saves: `StateFiles#written_slots`, `StateSlots#pick`, `#written_slots`, `#pictures`, `Saves::StatePictures`
      (a slot's picture from its state), TDD.
- [x] `Frontends::Driver`: a `pause_menu:` collaborator (`Driver::NoPauseMenu` by default), TDD.
- [x] `Pause::SlotPicker`, `Pause::Menu` and `Pause::Choice`; `CommandLine::MenuLoop` (a menu's loop in the window) and
      `CommandLine::Pause` (the game's menu and its choices), TDD.
- [x] `CommandLine::Game` (the pause menu, BACK TO THE LIST only from the list) and `CommandLine::Browser` (the list's
      menu), TDD.
- [x] README, `docs/architecture.md` (Frontends, Layout, decisions 113-116); no new acronym for `docs/GLOSSARY.md`;
      plan 40.

Refined while building:

- **The menu's loop split in four.** One unit running the menu and doing its choices would have made one large tree;
  it became `Pause::SlotPicker` (the slots and the picture in focus), `Pause::Menu` (the entries and the way into and
  out of the picker, giving a `Pause::Choice`), `CommandLine::MenuLoop` (the window's loop, shared with the list's
  menu) and `CommandLine::Pause` (doing the game's choice).
- **The menu's key is read after the frame is presented.** The window reads its keys as it presents a frame, so the
  Escape that opened the menu would close it at once if asked before; a button held as a menu opens is no press until
  let go.
- **`Screens::Colours` and `Screens::Layout`** hold the menus' colours and the browser's list layout, shared by the
  slot picker, so its picture and rows sit where the browser's do.
- **The entry reads BACK TO LIST**: the box is 16 columns wide, and BACK TO THE LIST does not fit beside the cursor.
- **A slot's picture is asked only for a slot that holds a state**, once per move of the focus.
- **The list's menu reads RESUME and QUIT**, the pause menu's labels: the scope's "BACK TO THE LIST" would read as
  the game menu's entry of that name, which leaves a game.
- **From the independent review:**
  - the A that chose BACK TO LIST started the game again in the list, and the A that chose RESUME in the list's menu
    started the ROM in focus: `Frontends::Base#next_screen` now keeps the buttons held from the next screen until let
    go, as `#resume` does, and the browser resumes the window after its menu;
  - L + R closing the pause menu opened it again at once: `Frontends::MenuCombination#restart`, called by `#resume`
    and `#next_screen`;
  - the slot picker keeps each slot's picture while it is open, as decision 4 says;
  - `Canvas#centred` centres within columns too, `CommandLine::Pause` takes its entries and state actions from
    `Pause::Menu`, `Browser::Menu::START` is `Screens::Choices::CHOOSE`, `StateSlots#select` became `#pick` (it hid
    `Kernel#select`);
  - a known limit, recorded: `HeldOver` learns a button was let go only when the buttons are read, which a game paused
    with P does not do, so a button held as a menu closed, let go while paused and held again stays hidden until let
    go once more;
  - an order-dependent failure of the window's `#notify` example, there before this plan, was fixed (the spy on
    `DrawText` was set before the library defined it).
- **Failure messages of specs that name a `Console` take minutes** (RSpec inspects it whole): the Game and Browser
  specs looked hung while red.

## Acceptance criteria

- [x] Escape and L + R open the pause menu over the dimmed game, in a game from the list and in `ruby-nes ROM`; from
      the keyboard and from the gamepad it resumes, saves and loads a state choosing the slot by its picture, resets,
      returns to the list (from the list only) and quits: specified (`Hotkeys`, `MenuCombination`, `Driver`,
      `Pause::Menu`, `Pause::SlotPicker`, `MenuLoop`, `CommandLine::Pause`, `Game`); the manual steps (How to test)
      were handed to the user, who approved the code on 2026-11-26.
- [x] Buttons held as the menu closes do not reach the game until released: specified (`HeldOver`, the window's
      `#resume` and `#next_screen` with its input stubbed); manual step 4.
- [x] In the list, Escape and L + R open its menu, and the program quits from the gamepad alone: specified
      (`Browser`, `MenuLoop`); manual step 6.
- [x] `quit:` in the config file still binds a key that quits, and `quit: escape` gives Escape its old meaning back
      (`KeyConfig` spec).
- [x] `rake bench:frames` keeps its digests (f0903fbc59bf / 10369a5b40df): `bench/frame.rb` under YJIT, 2026-11-26.
- [x] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green (3304 examples, 0 failures; 494 files, no offenses), branch
      coverage of each new unit, rubocop clean.

## What was done

- **Keys:** Escape is the `menu` hotkey (`quit` has no default key); L + R held together on gamepad 0 ask for the menu
  too (`Frontends::MenuCombination`). The window gained `menu_requested?`, `leave` (ends the screen), `quit` (ends the
  session) and `resume`; on `resume` and `next_screen` the hotkeys and the combination start over and
  `Frontends::HeldOver` keeps the buttons then held from the next screen until let go.
- **Shared screens:** `Frontends::Screens` took the font, presses and cursor out of the browser, and adds `Canvas`,
  `Colours`, `Layout`, `Shade` (the paused picture dimmed one value row, by a table of the 512 pixel values) and
  `Choices` (a column of entries).
- **The menus:** `Frontends::Pause::Menu` (entries over the dimmed picture, giving a `Pause::Choice`) and
  `Pause::SlotPicker` (the ten slots, each slot's picture read from its state by `Saves::StatePictures`, restored into
  a console of its own), drawn by `Pause::Screen`.
- **The loop:** `CommandLine::MenuLoop` runs a menu in the window; `Frontends::Driver` opens its `pause_menu:`
  (`CommandLine::Pause`, which does the choice) when asked, taking that turn; `CommandLine::Game` passes BACK TO LIST
  only from the list; `CommandLine::Browser` opens the list's menu (RESUME, QUIT).
- **Review:** two rounds; fixed a game started again by the A that chose BACK TO LIST, a ROM started by the A that
  chose RESUME in the list's menu, and L + R reopening the menu they closed; picture cache per slot; reuse and naming.
  Plan 40 (the controls screen) was split off.

## How to test

1. `bundle exec exe/ruby-nes`, start Super Mario Bros. 3, press Escape: the game, dimmed, under a box titled PAUSED.
2. SAVE STATE, slot 2, A: "State 2 saved", and Mario does not jump with A still held.
3. Play on, open the menu, LOAD STATE: move over the starred slots and see each one's picture; A on slot 2 returns to
   that moment.
4. On the pad: L + R opens the menu and L + R closes it, without reopening; hold Start, close with L + R, let go: the
   game does not pause.
5. BACK TO LIST with A on the pad: the list comes back and the game does not start again.
6. In the list, L + R opens the list's menu; QUIT closes ruby-nes, from the pad alone.
7. `bundle exec exe/ruby-nes roms/smb3.nes`: Escape opens the menu without BACK TO LIST; QUIT closes it.
8. The Legend of Zelda: play, BACK TO LIST, and its `.sav` is written.

## Glossary

- **Save state:** the whole machine at one moment, loaded back to return to it.
- **Slot:** one of the ten places (0-9) for a game's save states.
- **Dimmed:** each NES palette colour replaced by the same hue one value (luma) row lower.
- **L, R:** the shoulder buttons of a SNES-style pad, which an NES game never reads.

## References

- PPU palettes (a colour's index: luminance in bits 4-5, hue in bits 0-3; the blacks) —
  https://www.nesdev.org/wiki/PPU_palettes
- Overscan (lines 8-231) — https://www.nesdev.org/wiki/Overscan
- Standard controller (the buttons' report order, the masks the menus read) —
  https://www.nesdev.org/wiki/Standard_controller
- raylib cheatsheet (key and gamepad input) — https://www.raylib.com/cheatsheet/cheatsheet.html
- Plan 18 (key config, decision 7; hotkeys), plans 35, 36 (the pad's probe: L and R) and 37
