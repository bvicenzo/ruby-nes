# frozen_string_literal: true

module TestRoms
  # `test_rom_path` was asked for a ROM the example did not declare, so nothing checked that the file is intact.
  class UndeclaredRomError < StandardError; end

  # Lets a spec declare the test ROMs it needs, as a path of the manifest or a list of them, on a group, a nested group
  # or an example; an example needs every ROM declared on it and on the groups around it:
  #
  #   RSpec.describe 'nestest', test_rom: ['other/nestest.nes', 'other/nestest.log'] do
  #     it { expect(File.size(test_rom_path('other/nestest.nes'))).to eq(24_592) }
  #   end
  #
  # A path the manifest does not list fails as soon as the spec is defined. A group whose ROMs are missing or
  # corrupted is skipped before its own hooks run, with the command that fetches them; so is an example.
  module ExampleGroups
    # Methods available to the groups and examples that declare test ROMs, in examples and in group hooks alike.
    module Helpers
      def test_rom_path(path)
        unless ExampleGroups.declared_paths(self.class, RSpec.current_example).include?(path)
          raise UndeclaredRomError, "#{path} is not declared with test_rom: on this example or its groups"
        end

        RSpec.configuration.test_rom_requirement.path_of(path)
      end
    end

    def self.install(config, requirement:)
      config.add_setting(:test_rom_requirement)
      config.test_rom_requirement = requirement
      config.define_derived_metadata(:test_rom) { |metadata| requirement.ensure_listed(Array(metadata[:test_rom])) }
      config.include(Helpers, :test_rom)
      config.before(:context, :test_rom) do
        reason = requirement.skip_reason(ExampleGroups.declared_paths(self.class, nil))
        skip(reason) if reason
      end
      config.before(:example, :test_rom) do |example|
        reason = requirement.skip_reason(ExampleGroups.declared_paths(self.class, example))
        skip(reason) if reason
      end
    end

    # The ROMs declared on a group, the groups around it and, inside an example, the example itself. Metadata inherits
    # from the enclosing group, so each level adds its own declaration to the ones around it.
    def self.declared_paths(group, example)
      declarations = [example&.metadata, *group.parent_groups.map(&:metadata)].compact

      declarations.flat_map { |metadata| Array(metadata[:test_rom]) }.uniq
    end
  end
end
