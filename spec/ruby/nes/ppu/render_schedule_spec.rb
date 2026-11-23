# frozen_string_literal: true

# The rendering work of each dot (https://www.nesdev.org/wiki/PPU_rendering, https://www.nesdev.org/wiki/PPU_scrolling).
# On the visible (0-239) and pre-render (261) scanlines with rendering enabled: each tile's nametable, attribute, low
# and high pattern fetches take 2 dots each (dots 1-256 and 321-336, done on the first dot of each pair); "The
# shifters are reloaded during ticks 9, 17, 25, ..., 257" and with the two tiles of 321-336 (dots 329 and 337);
# coarse X increments at 8, 16, ..., 256, 328 and 336; Y at 256; the horizontal copy at 257; the vertical copy at
# 280-304 of the pre-render line. Visible lines draw dots 1-256 (x = dot - 1, plan 13 decision 5) and shift then; the
# shifts of 321-336 bring the next line's first two tiles in. With rendering disabled, visible lines draw the forced
# blank and nothing else happens but the sprite line's clear (below). The garbage nametable fetches of 257-320 and
# 337-340 are not made (decision 6).
#
# Sprites (plan 14): the evaluation runs once per visible scanline at dot 257, for the next line (decision 2), after the
# line buffer is cleared; "Sprite evaluation does not happen on the pre-render scanline"
# (https://www.nesdev.org/wiki/PPU_sprite_evaluation), whose line buffer is only cleared ("no sprites will be rendered
# on the first scanline"). Dots 257-320 fetch 8 sprites, 8 dots each, "Pattern table tile low" and "Pattern table tile
# high" being the third and fourth 2-dot accesses (https://www.nesdev.org/wiki/PPU_rendering): 261 + 8k and 263 + 8k
# (decision 3); the pre-render line makes them too but loads nothing. With rendering disabled no sprite is fetched, so
# visible and pre-render lines still clear the line at 257: a sprite output unit shows its row once, on the line after
# its fetch (a derivation from "sprite output units" loaded at 257-320, https://www.nesdev.org/wiki/PPU_OAM).
# "OAMADDR is set to 0 during each of ticks 257–320 (the sprite tile loading interval) of the pre-render and visible
# scanlines" (https://www.nesdev.org/wiki/PPU_registers).
#
# The first dot of each of the 32 tiles a visible line draws (1, 9, ..., 249) also says the tile can run whole: its 8
# dots are always the same steps (plan 28, decision 6).
RSpec.describe Ruby::Nes::Ppu::RenderSchedule do
  # The steps of each dot of a scanline, one array per kind of line (plan 28, decision 4).
  describe '#line' do
    context 'when rendering is disabled' do
      subject(:schedule) { described_class.new(rendering_enabled: false) }

      context 'and the scanline is visible' do
        context 'and the dot is 0' do
          it 'does nothing' do
            expect(schedule.line(239)[0]).to eq(0)
          end
        end

        context 'and the dot is 1' do
          it 'draws a forced blank pixel' do
            expect(schedule.line(239)[1]).to eq(described_class::FORCED_BLANK_PIXEL)
          end
        end

        context 'and the dot is 256' do
          it 'draws a forced blank pixel' do
            expect(schedule.line(239)[256]).to eq(described_class::FORCED_BLANK_PIXEL)
          end
        end

        context 'and the dot is 257' do
          it 'clears the sprite line' do
            expect(schedule.line(239)[257]).to eq(described_class::CLEAR_SPRITE_LINE)
          end
        end
      end

      context 'and the scanline is the post-render one' do
        it 'does nothing' do
          expect(schedule.line(240)[1]).to eq(0)
        end
      end

      context 'and the scanline is the pre-render one' do
        context 'and the dot is 1' do
          it 'does nothing' do
            expect(schedule.line(261)[1]).to eq(0)
          end
        end

        context 'and the dot is 257' do
          it 'clears the sprite line' do
            expect(schedule.line(261)[257]).to eq(described_class::CLEAR_SPRITE_LINE)
          end
        end

        context 'and the dot is 280' do
          it 'does nothing' do
            expect(schedule.line(261)[280]).to eq(0)
          end
        end
      end
    end

    context 'when rendering is enabled' do
      subject(:schedule) { described_class.new(rendering_enabled: true) }

      context 'and the scanline is visible' do
        context 'and the dot is 0' do
          it 'does nothing' do
            expect(schedule.line(239)[0]).to eq(0)
          end
        end

        context 'and the dot is 1, the first of a tile' do
          it 'draws a pixel, shifts, fetches the nametable byte and starts a whole tile' do
            expect(schedule.line(239)[1]).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::FETCH_NAMETABLE |
              described_class::WHOLE_TILE
            )
          end
        end

        context 'and the dot is 2' do
          it 'draws a pixel and shifts' do
            expect(schedule.line(239)[2]).to eq(described_class::PIXEL | described_class::SHIFT)
          end
        end

        context 'and the dot is 3' do
          it 'draws a pixel, shifts and fetches the attribute byte' do
            expect(schedule.line(239)[3]).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::FETCH_ATTRIBUTE
            )
          end
        end

        context 'and the dot is 5' do
          it 'draws a pixel, shifts and fetches the low pattern byte' do
            expect(schedule.line(239)[5]).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::FETCH_PATTERN_LOW
            )
          end
        end

        context 'and the dot is 7' do
          it 'draws a pixel, shifts and fetches the high pattern byte' do
            expect(schedule.line(239)[7]).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::FETCH_PATTERN_HIGH
            )
          end
        end

        context 'and the dot is 8, the last of a tile' do
          it 'draws a pixel, shifts and increments coarse X' do
            expect(schedule.line(239)[8]).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::INCREMENT_COARSE_X
            )
          end
        end

        context 'and the dot is 9, the first of the next tile' do
          it 'draws a pixel, reloads the shifters, shifts, fetches the nametable byte and starts a whole tile' do
            expect(schedule.line(239)[9]).to eq(
              described_class::PIXEL |
              described_class::RELOAD |
              described_class::SHIFT |
              described_class::FETCH_NAMETABLE |
              described_class::WHOLE_TILE
            )
          end
        end

        context 'and the dot is 249, the first of the last tile' do
          it 'draws a pixel, reloads the shifters, shifts, fetches the nametable byte and starts a whole tile' do
            expect(schedule.line(239)[249]).to eq(
              described_class::PIXEL |
              described_class::RELOAD |
              described_class::SHIFT |
              described_class::FETCH_NAMETABLE |
              described_class::WHOLE_TILE
            )
          end
        end

        context 'and the dot is 256, the last pixel' do
          it 'draws a pixel, shifts, increments coarse X and increments Y' do
            expect(schedule.line(239)[256]).to eq(
              described_class::PIXEL |
              described_class::SHIFT |
              described_class::INCREMENT_COARSE_X |
              described_class::INCREMENT_Y
            )
          end
        end

        context 'and the dot is 257' do
          it 'reloads, copies the horizontal position, clears the sprite line, evaluates and resets OAMADDR' do
            expect(schedule.line(239)[257]).to eq(
              described_class::RELOAD |
              described_class::COPY_HORIZONTAL |
              described_class::CLEAR_SPRITE_LINE |
              described_class::EVALUATE_SPRITES |
              described_class::RESET_OAM_ADDRESS
            )
          end
        end

        context 'and the dot is 258' do
          it 'resets OAMADDR' do
            expect(schedule.line(239)[258]).to eq(described_class::RESET_OAM_ADDRESS)
          end
        end

        context 'and the dot is 261, the low pattern fetch of the first sprite' do
          it "fetches the sprite's low pattern byte and resets OAMADDR" do
            expect(schedule.line(239)[261]).to eq(
              described_class::FETCH_SPRITE_LOW |
              described_class::RESET_OAM_ADDRESS
            )
          end
        end

        context 'and the dot is 263, the high pattern fetch of the first sprite' do
          it "fetches the sprite's high pattern byte, loads the sprite and resets OAMADDR" do
            expect(schedule.line(239)[263]).to eq(
              described_class::FETCH_SPRITE_HIGH |
              described_class::RESET_OAM_ADDRESS |
              described_class::LOAD_SPRITE
            )
          end
        end

        context 'and the dot is 279, the high pattern fetch of the third sprite' do
          it "fetches the sprite's high pattern byte, loads the sprite and resets OAMADDR" do
            expect(schedule.line(239)[279]).to eq(
              described_class::FETCH_SPRITE_HIGH |
              described_class::RESET_OAM_ADDRESS |
              described_class::LOAD_SPRITE
            )
          end
        end

        context 'and the dot is 280' do
          it 'resets OAMADDR' do
            expect(schedule.line(239)[280]).to eq(described_class::RESET_OAM_ADDRESS)
          end
        end

        context 'and the dot is 304' do
          it 'resets OAMADDR' do
            expect(schedule.line(239)[304]).to eq(described_class::RESET_OAM_ADDRESS)
          end
        end

        context 'and the dot is 305' do
          it 'resets OAMADDR' do
            expect(schedule.line(239)[305]).to eq(described_class::RESET_OAM_ADDRESS)
          end
        end

        context 'and the dot is 317, the low pattern fetch of the eighth sprite' do
          it "fetches the sprite's low pattern byte and resets OAMADDR" do
            expect(schedule.line(239)[317]).to eq(
              described_class::FETCH_SPRITE_LOW |
              described_class::RESET_OAM_ADDRESS
            )
          end
        end

        context 'and the dot is 319, the high pattern fetch of the eighth sprite' do
          it "fetches the sprite's high pattern byte, loads the sprite and resets OAMADDR" do
            expect(schedule.line(239)[319]).to eq(
              described_class::FETCH_SPRITE_HIGH |
              described_class::RESET_OAM_ADDRESS |
              described_class::LOAD_SPRITE
            )
          end
        end

        context 'and the dot is 320' do
          it 'resets OAMADDR' do
            expect(schedule.line(239)[320]).to eq(described_class::RESET_OAM_ADDRESS)
          end
        end

        context "and the dot is 321, the first of the next line's first tile" do
          it 'shifts and fetches the nametable byte' do
            expect(schedule.line(239)[321]).to eq(described_class::SHIFT | described_class::FETCH_NAMETABLE)
          end
        end

        context 'and the dot is 328' do
          it 'shifts and increments coarse X' do
            expect(schedule.line(239)[328]).to eq(described_class::SHIFT | described_class::INCREMENT_COARSE_X)
          end
        end

        context "and the dot is 329, the first of the next line's second tile" do
          it 'reloads the shifters, shifts and fetches the nametable byte' do
            expect(schedule.line(239)[329]).to eq(
              described_class::RELOAD |
              described_class::SHIFT |
              described_class::FETCH_NAMETABLE
            )
          end
        end

        context 'and the dot is 336' do
          it 'shifts and increments coarse X' do
            expect(schedule.line(239)[336]).to eq(described_class::SHIFT | described_class::INCREMENT_COARSE_X)
          end
        end

        context 'and the dot is 337' do
          it 'reloads the shifters' do
            expect(schedule.line(239)[337]).to eq(described_class::RELOAD)
          end
        end

        context 'and the dot is 338' do
          it 'does nothing' do
            expect(schedule.line(239)[338]).to eq(0)
          end
        end
      end

      context 'and the scanline is the post-render one' do
        it 'does nothing' do
          expect(schedule.line(240)[1]).to eq(0)
        end
      end

      context 'and the scanline is the last of VBlank' do
        it 'does nothing' do
          expect(schedule.line(260)[1]).to eq(0)
        end
      end

      context 'and the scanline is the pre-render one' do
        context 'and the dot is 0' do
          it 'does nothing' do
            expect(schedule.line(261)[0]).to eq(0)
          end
        end

        context 'and the dot is 1, the first of a tile' do
          it 'shifts and fetches the nametable byte' do
            expect(schedule.line(261)[1]).to eq(described_class::SHIFT | described_class::FETCH_NAMETABLE)
          end
        end

        context 'and the dot is 2' do
          it 'shifts' do
            expect(schedule.line(261)[2]).to eq(described_class::SHIFT)
          end
        end

        context 'and the dot is 3' do
          it 'shifts and fetches the attribute byte' do
            expect(schedule.line(261)[3]).to eq(described_class::SHIFT | described_class::FETCH_ATTRIBUTE)
          end
        end

        context 'and the dot is 5' do
          it 'shifts and fetches the low pattern byte' do
            expect(schedule.line(261)[5]).to eq(described_class::SHIFT | described_class::FETCH_PATTERN_LOW)
          end
        end

        context 'and the dot is 7' do
          it 'shifts and fetches the high pattern byte' do
            expect(schedule.line(261)[7]).to eq(described_class::SHIFT | described_class::FETCH_PATTERN_HIGH)
          end
        end

        context 'and the dot is 8, the last of a tile' do
          it 'shifts and increments coarse X' do
            expect(schedule.line(261)[8]).to eq(described_class::SHIFT | described_class::INCREMENT_COARSE_X)
          end
        end

        context 'and the dot is 9, the first of the next tile' do
          it 'reloads the shifters, shifts and fetches the nametable byte' do
            expect(schedule.line(261)[9]).to eq(
              described_class::RELOAD |
              described_class::SHIFT |
              described_class::FETCH_NAMETABLE
            )
          end
        end

        context 'and the dot is 256, the last pixel' do
          it 'shifts, increments coarse X and increments Y' do
            expect(schedule.line(261)[256]).to eq(
              described_class::SHIFT |
              described_class::INCREMENT_COARSE_X |
              described_class::INCREMENT_Y
            )
          end
        end

        context 'and the dot is 257' do
          it 'reloads, copies the horizontal position, clears the sprite line and resets OAMADDR' do
            expect(schedule.line(261)[257]).to eq(
              described_class::RELOAD |
              described_class::COPY_HORIZONTAL |
              described_class::CLEAR_SPRITE_LINE |
              described_class::RESET_OAM_ADDRESS
            )
          end
        end

        context 'and the dot is 258' do
          it 'resets OAMADDR' do
            expect(schedule.line(261)[258]).to eq(described_class::RESET_OAM_ADDRESS)
          end
        end

        context 'and the dot is 261, the low pattern fetch of the first sprite' do
          it "fetches the sprite's low pattern byte and resets OAMADDR" do
            expect(schedule.line(261)[261]).to eq(
              described_class::FETCH_SPRITE_LOW |
              described_class::RESET_OAM_ADDRESS
            )
          end
        end

        context 'and the dot is 263, the high pattern fetch of the first sprite' do
          it "fetches the sprite's high pattern byte and resets OAMADDR" do
            expect(schedule.line(261)[263]).to eq(
              described_class::FETCH_SPRITE_HIGH |
              described_class::RESET_OAM_ADDRESS
            )
          end
        end

        context 'and the dot is 279, the high pattern fetch of the third sprite' do
          it "fetches the sprite's high pattern byte and resets OAMADDR" do
            expect(schedule.line(261)[279]).to eq(
              described_class::FETCH_SPRITE_HIGH |
              described_class::RESET_OAM_ADDRESS
            )
          end
        end

        context 'and the dot is 280' do
          it 'copies the vertical position and resets OAMADDR' do
            expect(schedule.line(261)[280]).to eq(described_class::COPY_VERTICAL | described_class::RESET_OAM_ADDRESS)
          end
        end

        context 'and the dot is 304' do
          it 'copies the vertical position and resets OAMADDR' do
            expect(schedule.line(261)[304]).to eq(described_class::COPY_VERTICAL | described_class::RESET_OAM_ADDRESS)
          end
        end

        context 'and the dot is 305' do
          it 'resets OAMADDR' do
            expect(schedule.line(261)[305]).to eq(described_class::RESET_OAM_ADDRESS)
          end
        end

        context 'and the dot is 317, the low pattern fetch of the eighth sprite' do
          it "fetches the sprite's low pattern byte and resets OAMADDR" do
            expect(schedule.line(261)[317]).to eq(
              described_class::FETCH_SPRITE_LOW |
              described_class::RESET_OAM_ADDRESS
            )
          end
        end

        context 'and the dot is 319, the high pattern fetch of the eighth sprite' do
          it "fetches the sprite's high pattern byte and resets OAMADDR" do
            expect(schedule.line(261)[319]).to eq(
              described_class::FETCH_SPRITE_HIGH |
              described_class::RESET_OAM_ADDRESS
            )
          end
        end

        context 'and the dot is 320' do
          it 'resets OAMADDR' do
            expect(schedule.line(261)[320]).to eq(described_class::RESET_OAM_ADDRESS)
          end
        end

        context "and the dot is 321, the first of the next line's first tile" do
          it 'shifts and fetches the nametable byte' do
            expect(schedule.line(261)[321]).to eq(described_class::SHIFT | described_class::FETCH_NAMETABLE)
          end
        end

        context 'and the dot is 328' do
          it 'shifts and increments coarse X' do
            expect(schedule.line(261)[328]).to eq(described_class::SHIFT | described_class::INCREMENT_COARSE_X)
          end
        end

        context "and the dot is 329, the first of the next line's second tile" do
          it 'reloads the shifters, shifts and fetches the nametable byte' do
            expect(schedule.line(261)[329]).to eq(
              described_class::RELOAD |
              described_class::SHIFT |
              described_class::FETCH_NAMETABLE
            )
          end
        end

        context 'and the dot is 336' do
          it 'shifts and increments coarse X' do
            expect(schedule.line(261)[336]).to eq(described_class::SHIFT | described_class::INCREMENT_COARSE_X)
          end
        end

        context 'and the dot is 337' do
          it 'reloads the shifters' do
            expect(schedule.line(261)[337]).to eq(described_class::RELOAD)
          end
        end

        context 'and the dot is 338' do
          it 'does nothing' do
            expect(schedule.line(261)[338]).to eq(0)
          end
        end
      end
    end
  end

  describe '#rendering_enabled=' do
    context 'when rendering is turned on' do
      subject(:schedule) { described_class.new(rendering_enabled: false) }

      it 'schedules the rendering steps' do
        schedule.rendering_enabled = true
        expect(schedule.line(0)[2]).to eq(described_class::PIXEL | described_class::SHIFT)
      end
    end

    context 'when rendering is turned off' do
      subject(:schedule) { described_class.new(rendering_enabled: true) }

      it 'schedules the forced blank' do
        schedule.rendering_enabled = false
        expect(schedule.line(0)[1]).to eq(described_class::FORCED_BLANK_PIXEL)
      end
    end
  end
end
