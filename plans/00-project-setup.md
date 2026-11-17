# 00 — Project setup

**Status:** done (2026-11-17)
**Depends on:** —

## Goal

A gem skeleton ready for test-driven work on Ruby 4.0.9, with the user's lint rules, a non-MIT license and the
working agreements written down.

## What was done

- `bundle gem ruby-nes --test=rspec --linter=rubocop --exe` → gem `ruby-nes`, namespace `Ruby::Nes`.
- License: GPL-3.0-or-later (`LICENSE`, gemspec `license`).
- Ruby pinned to 4.0.9 (`mise.toml`, gemspec `required_ruby_version >= 4.0.0`).
- RuboCop: `inherit_gem: rubocop-vicenzo: config/style.yml` + `rubocop-rake`; `TargetRubyVersion: 4.0`.
- RSpec: random order, partial double verification, `--only-failures` support; SimpleCov branch coverage behind
  `COVERAGE=1`.
- Generator placeholders removed (failing example spec, TODOs in gemspec/README).
- `.gitignore`: `coverage/`, `tmp/`, `roms/`, `*.nes`.
- `roms/smb3.nes` symlink to the user's dump (ignored by git).
- `CLAUDE.md` with language, plan, TDD and style rules.
- Global skill `~/.claude/skills/ruby-code-style` derived from the Fretadao `rails-code-style` skill, without Rails-
  or company-specific content.

## Acceptance criteria

- [x] `bundle install` succeeds on Ruby 4.0.9.
- [x] `bundle exec rspec` runs (0 examples, 0 failures).
- [x] `bundle exec rubocop` reports no offenses.
- [x] `LICENSE` contains the GPL v3 text and the gemspec declares `GPL-3.0-or-later`.
- [x] No ROM file is tracked by git.

## References

- Bundler `bundle gem` — https://bundler.io/man/bundle-gem.1.html
- rubocop-vicenzo — https://github.com/bvicenzo/rubocop-vicenzo
- GPL v3 — https://www.gnu.org/licenses/gpl-3.0.html
