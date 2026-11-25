# frozen_string_literal: true

require_relative 'support/test_roms/sandboxed_group'

RSpec.describe FrontendLibraries do
  describe '.install' do
    let(:install_hook) { ->(config) { described_class.install(config) } }

    context 'when nothing declares a frontend library' do
      subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(&install_hook) }

      it 'runs the group' do
        expect(sandboxed_run.execution_result.status).to eq(:passed)
      end
    end

    context 'when a group declares a frontend library' do
      context 'but it cannot be loaded' do
        subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(group_metadata:, group_hook_body:, &install_hook) }

        let(:group_metadata) { [{ frontend_library: 'ruby/nes/frontends/absent_backend' }] }
        let(:group_hook_body) { -> { raise 'the group hook ran' } }

        it 'skips the group before its own hooks run, naming the library' do
          expect(sandboxed_run.execution_result)
            .to have_attributes(status: :pending, pending_message: a_string_including('absent_backend'))
        end
      end

      context 'and it loads' do
        subject(:sandboxed_run) { TestRoms::SandboxedGroup.run(group_metadata:, &install_hook) }

        let(:group_metadata) { [{ frontend_library: 'ruby/nes/frontends/controls' }] }

        it 'runs the group' do
          expect(sandboxed_run.execution_result.status).to eq(:passed)
        end
      end
    end
  end
end
