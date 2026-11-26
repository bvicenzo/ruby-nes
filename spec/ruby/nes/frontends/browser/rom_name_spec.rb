# frozen_string_literal: true

require 'ruby/nes/frontends/browser'

# The name the ROM browser shows for a ROM file (plan 37, decision 4): its file name, without the folder and the
# extension, in upper case, as the pixel font has no lower case. The No-Intro tags, the parts in brackets such as
# "(USA)" and "(Rev 1)", are left out of the name and kept apart, to show under the preview; a file name made of tags
# alone keeps them as its name. Both are printable (Screens::PixelFont.printable), so they can always be drawn.
RSpec.describe Ruby::Nes::Frontends::Browser::RomName do
  describe '.of' do
    context 'when the file name has no tags' do
      it 'is the file name without its folder and extension, in upper case, with no tags' do
        expect(described_class.of('roms/Mario Bros. Classic.nes'))
          .to have_attributes(name: 'MARIO BROS. CLASSIC', tags: '')
      end
    end

    context 'when the file name has tags' do
      context 'but nothing else' do
        it 'keeps them as the name, with no tags' do
          expect(described_class.of('roms/(Unl) [b1].nes')).to have_attributes(name: '(UNL) [B1]', tags: '')
        end
      end

      context 'and a title' do
        it 'is the title, with the tags apart', :aggregate_failures do
          rom_name = described_class.of('roms/Legend of Zelda, The (USA) (Rev 1) [!].nes')

          expect(rom_name.name).to eq('LEGEND OF ZELDA, THE')
          expect(rom_name.tags).to eq('(USA) (REV 1) [!]')
        end
      end
    end

    context 'when the file name has characters the font cannot draw as they are' do
      it 'makes the name and the tags printable' do
        expect(described_class.of('roms/Pokémon~Puzzle (Évora).nes'))
          .to have_attributes(name: 'POKEMON?PUZZLE', tags: '(EVORA)')
      end
    end
  end
end
