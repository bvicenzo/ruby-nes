# frozen_string_literal: true

# Dumps of the user's own cartridges, kept under roms/ and never committed (CLAUDE.md, ROMs). A spec declares the
# ones it needs, as a name or a list of names, on a group, a nested group or an example, and reads their paths with
# `local_rom_path`:
#
#   RSpec.describe 'Super Mario Bros. 3', local_rom: 'smb3.nes' do
#     it { expect(File.size(local_rom_path('smb3.nes'))).to eq(393_232) }
#   end
#
# A group whose dumps are absent (always the case in CI) is skipped before its own hooks run; so is an example.
module LocalRoms
  DIRECTORY = File.expand_path('../../roms', __dir__)

  # `local_rom_path` was asked for a dump the example did not declare, so nothing checked that the file is there.
  class UndeclaredRomError < StandardError; end

  # Methods available to the groups and examples that declare local ROMs, in examples and in group hooks alike.
  module Helpers
    def local_rom_path(name)
      unless LocalRoms.declared_names(self.class, RSpec.current_example).include?(name)
        raise UndeclaredRomError, "#{name} is not declared with local_rom: on this example or its groups"
      end

      File.join(RSpec.configuration.local_rom_directory, name)
    end
  end

  def self.install(config, directory:)
    config.add_setting(:local_rom_directory)
    config.local_rom_directory = directory
    config.include(Helpers, :local_rom)
    config.before(:context, :local_rom) do
      reason = LocalRoms.skip_reason(directory, LocalRoms.declared_names(self.class, nil))
      skip(reason) if reason
    end
    config.before(:example, :local_rom) do |example|
      reason = LocalRoms.skip_reason(directory, LocalRoms.declared_names(self.class, example))
      skip(reason) if reason
    end
  end

  # The names declared on a group, the groups around it and, inside an example, the example itself. Metadata inherits
  # from the enclosing group, so each level adds its own declaration to the ones around it. A group's before(:context)
  # hook also runs when only an example inside it declares a local ROM; the group then declares none of its own.
  def self.declared_names(group, example)
    declarations = [example&.metadata, *group.parent_groups.map(&:metadata)].compact

    declarations.flat_map { |metadata| Array(metadata[:local_rom]) }.uniq
  end

  def self.skip_reason(directory, names)
    absent_paths = names.map { |name| File.join(directory, name) }.reject { |path| File.exist?(path) }
    return if absent_paths.empty?

    "Local ROMs absent (#{absent_paths.join(', ')}): place dumps of your own cartridges there (never committed)"
  end
end
