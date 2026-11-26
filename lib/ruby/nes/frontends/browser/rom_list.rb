# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Browser
        # The ROMs of a folder, as the browser lists them (plan 37, scope 2): the `.nes` files at its top, in any case,
        # except hidden ones (macOS writes "._" files named like the ones it copies), sorted by the name shown, each a
        # Browser::Rom. Whether ruby-nes can run one is read from its iNES header alone
        # (https://www.nesdev.org/wiki/INES), so a folder of large ROMs lists at once: a file that cannot be read, an
        # image that is not iNES, or a mapper with no board here (Mappers::BOARDS), is its problem. Its marks come from
        # what the saves directory (Saves::Directory) keeps for it. Off the hot path: once per scan.
        module RomList
          EXTENSION = '.nes'
          HIDDEN = '.'
          NOT_INES = 'NOT AN INES IMAGE'
          UNREADABLE = 'CANNOT BE READ'

          # The ROMs in `folder`; raises SystemCallError when it cannot be read, and Saves::Error when `directory`
          # cannot be found.
          def self.scan(folder, directory:)
            Dir
              .children(folder)
              .select { File.extname(it).casecmp?(EXTENSION) && !it.start_with?(HIDDEN) }
              .map { File.join(folder, it) }
              .select { File.file?(it) }
              .map { rom(it, directory) }
              .sort_by { [it.name, it.path] }
          end

          def self.rom(path, directory)
            rom_name = RomName.of(path)
            Rom.new(
              path:,
              name: rom_name.name,
              tags: rom_name.tags,
              problem: problem(path),
              battery_save: File.file?(directory.battery_save_path(path)),
              save_states: !Saves::StateFiles.new(directory:, rom_path: path).latest_slot.nil?
            )
          end

          def self.problem(path)
            mapper_number = Cartridge::Header.parse(File.binread(path, Cartridge::Header::SIZE).to_s).mapper_number
            "MAPPER #{mapper_number} IS NOT SUPPORTED" unless Mappers::BOARDS.has_key?(mapper_number)
          rescue Cartridge::InvalidImage
            NOT_INES
          rescue SystemCallError
            UNREADABLE
          end

          private_class_method :rom, :problem
        end
      end
    end
  end
end
