# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'ruby/nes/saves'
require 'ruby/nes/frontends/browser'

# The ROMs the browser lists (plan 37, scope 2): the `.nes` files at the top of a folder (in any case; hidden ones,
# starting with a dot, left out), sorted by the name shown (Browser::RomName), each with its tags, the reason ruby-nes
# cannot run it, read from its 16-byte iNES header alone (https://www.nesdev.org/wiki/INES): a file that cannot be
# read, not an iNES image, or a mapper with no board here (Mappers::BOARDS), and marks for the saves Saves::Directory
# keeps for it: a battery save (plan 34) and save states (plan 35). A folder that cannot be read raises.
RSpec.describe Ruby::Nes::Frontends::Browser::RomList do
  describe '.scan' do
    context 'when the folder does not exist' do
      let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => '/nowhere' }) }

      it 'raises' do
        expect { described_class.scan('/nowhere/roms', directory:) }.to raise_error(Errno::ENOENT)
      end
    end

    context 'when the folder exists' do
      let(:folder) { Dir.mktmpdir }
      let(:data_home) { Dir.mktmpdir }
      let(:directory) { Ruby::Nes::Saves::Directory.new(environment: { 'XDG_DATA_HOME' => data_home }) }

      after do
        FileUtils.remove_entry(folder)
        FileUtils.remove_entry(data_home)
      end

      context 'but it holds no ROM' do
        before do
          File.write(File.join(folder, 'notes.txt'), 'notes')
          FileUtils.mkdir_p(File.join(folder, 'more'))
          File.binwrite(File.join(folder, 'more', 'Inside.nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
        end

        it 'is empty' do
          expect(described_class.scan(folder, directory:)).to be_empty
        end
      end

      context 'and it holds ROMs' do
        context 'and other files' do
          before do
            File.binwrite(File.join(folder, 'Zelda.nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
            File.binwrite(File.join(folder, 'castlevania.NES'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
            File.write(File.join(folder, 'notes.txt'), 'notes')
            FileUtils.mkdir_p(File.join(folder, 'more'))
            File.binwrite(File.join(folder, 'more', 'Inside.nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
          end

          it 'lists only the ROMs at the top of the folder, sorted by name' do
            expect(described_class.scan(folder, directory:).map(&:path))
              .to eq([File.join(folder, 'castlevania.NES'), File.join(folder, 'Zelda.nes')])
          end
        end

        # macOS writes "._" files beside the ones it copies to some disks (AppleDouble), named like them.
        context 'and a hidden file named like one' do
          before do
            File.binwrite(File.join(folder, 'Zelda.nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
            File.binwrite(File.join(folder, '._Zelda.nes'), 'Mac OS X resource fork')
          end

          it 'leaves it out' do
            expect(described_class.scan(folder, directory:).map(&:path)).to eq([File.join(folder, 'Zelda.nes')])
          end
        end

        context 'and one cannot be read' do
          before do
            File.binwrite(File.join(folder, 'Locked.nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
            File.chmod(0o000, File.join(folder, 'Locked.nes'))
          end

          it 'gives the reason it cannot be run' do
            expect(described_class.scan(folder, directory:).first.problem).to eq('CANNOT BE READ')
          end
        end

        context 'and one is not an iNES image' do
          before { File.write(File.join(folder, 'Notes.nes'), 'not a cartridge, but long enough for a header') }

          it 'gives the reason it cannot be run' do
            expect(described_class.scan(folder, directory:).first.problem).to eq('NOT AN INES IMAGE')
          end
        end

        context 'and one has a mapper ruby-nes does not support' do
          before do
            File.binwrite(
              File.join(folder, 'Castlevania III.nes'),
              Cartridges.ines_image(prg_rom: Array.new(16_384, 0), mapper_number: 5)
            )
          end

          it 'gives the reason it cannot be run' do
            expect(described_class.scan(folder, directory:).first.problem).to eq('MAPPER 5 IS NOT SUPPORTED')
          end
        end

        context 'and one can be run' do
          context 'and it has a battery save' do
            before do
              File.binwrite(File.join(folder, 'Zelda (USA).nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
              FileUtils.mkdir_p(File.join(data_home, 'ruby-nes', 'saves'))
              File.binwrite(File.join(data_home, 'ruby-nes', 'saves', 'Zelda (USA).sav'), 'save')
            end

            it 'is marked with it' do
              expect(described_class.scan(folder, directory:).first).to have_attributes(
                path: File.join(folder, 'Zelda (USA).nes'),
                name: 'ZELDA',
                tags: '(USA)',
                problem: nil,
                battery_save: true,
                save_states: false
              )
            end
          end

          context 'and it has save states' do
            before do
              File.binwrite(File.join(folder, 'Zelda (USA).nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
              FileUtils.mkdir_p(File.join(data_home, 'ruby-nes', 'states', 'Zelda (USA)'))
              File.binwrite(File.join(data_home, 'ruby-nes', 'states', 'Zelda (USA)', '4.state'), 'state')
            end

            it 'is marked with them' do
              expect(described_class.scan(folder, directory:).first).to have_attributes(
                path: File.join(folder, 'Zelda (USA).nes'),
                name: 'ZELDA',
                tags: '(USA)',
                problem: nil,
                battery_save: false,
                save_states: true
              )
            end
          end

          context 'and it has no saves' do
            before do
              File.binwrite(File.join(folder, 'Zelda (USA).nes'), Cartridges.ines_image(prg_rom: Array.new(16_384, 0)))
            end

            it 'has no marks' do
              expect(described_class.scan(folder, directory:).first).to have_attributes(
                path: File.join(folder, 'Zelda (USA).nes'),
                name: 'ZELDA',
                tags: '(USA)',
                problem: nil,
                battery_save: false,
                save_states: false
              )
            end
          end
        end
      end
    end
  end
end
