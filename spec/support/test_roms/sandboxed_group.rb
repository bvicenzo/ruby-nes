# frozen_string_literal: true

require 'rspec/core/sandbox'

module TestRoms
  # Runs one example inside an RSpec sandbox, so the spec of the test ROM hook can watch what the hook does to it
  # without touching the real suite. The block configures the sandbox. `group_metadata` lists the metadata of each
  # group from the outermost to the innermost (one entry per nesting level). `group_hook_body` runs in a
  # `before(:context)` of the outermost group and `example_body` in the example; their values are returned.
  module SandboxedGroup
    Run = Data.define(:execution_result, :group_hook_value, :example_value)

    def self.run(group_metadata: [{}], example_metadata: {}, group_hook_body: -> {}, example_body: -> {})
      RSpec::Core::Sandbox.sandboxed do |config|
        yield config
        # A skip in a before(:context) hook marks RSpec.current_example, which no sandboxed example has set yet: it
        # would still be the caller's example and the caller would be skipped instead.
        RSpec.current_example = nil
        group_hook_value = nil
        example_value = nil
        outermost_metadata, *nested_metadata = group_metadata
        outermost_group = RSpec.describe('a sandboxed group', **outermost_metadata)
        outermost_group.before(:context) { group_hook_value = instance_exec(&group_hook_body) }
        innermost_group = nested_metadata
          .reduce(outermost_group) { |parent, metadata| parent.context('nested', **metadata) }
        innermost_group.it('runs', **example_metadata) { example_value = instance_exec(&example_body) }
        outermost_group.run
        Run.new(execution_result: innermost_group.examples.first.execution_result, group_hook_value:, example_value:)
      end
    end
  end
end
