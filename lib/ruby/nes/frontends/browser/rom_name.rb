# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Browser
        # The name the ROM browser shows for a ROM file, and its No-Intro tags apart (plan 37, decision 4), both
        # printable (Screens::PixelFont.printable). Off the hot path: once per file listed.
        RomName = Data.define(:name, :tags)

        class RomName
          # A part of the file name in round or square brackets, such as "(USA)" or "[!]".
          TAG = /\([^)]*\)|\[[^\]]*\]/
          SPACES = /\s+/

          # The name and tags of the ROM at `path`: its file name without the extension. A file name made of tags alone
          # is its own name, with no tags.
          def self.of(path)
            file_name = Screens::PixelFont.printable(File.basename(path, '.*'))
            tags = file_name.scan(TAG)
            title = squeezed(file_name.gsub(TAG, ''))
            return new(name: squeezed(file_name), tags: '') if title.empty?

            new(name: title, tags: tags.join(' '))
          end

          def self.squeezed(text) = text.gsub(SPACES, ' ').strip

          private_class_method :squeezed
        end
      end
    end
  end
end
