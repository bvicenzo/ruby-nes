# frozen_string_literal: true

require 'ruby/nes/saves'

# The values of a namespace's constants, its inner modules' included, as one digest (plan 35, decision 2; review): a
# save state records the core's, so a state saved before a change to a table the console reads (a waveform, a frame
# counter's steps) is refused, as the state would carry the old table. Constants are named relative to the namespace,
# so two namespaces compare; the modules given as exceptions (the frontends, which a state does not hold) are left
# out.
RSpec.describe Ruby::Nes::Saves::ConstantsDigest do
  describe '.of' do
    let(:machine_digest) { described_class.of(ConstantSamples::Machine, except: [:Frontend]) }

    context 'when the constants have the same names and values' do
      it 'is the same' do
        expect(described_class.of(ConstantSamples::SameMachine, except: [:Frontend])).to eq(machine_digest)
      end
    end

    context 'when a constant of the namespace differs' do
      it 'differs' do
        expect(described_class.of(ConstantSamples::MachineWithOtherSteps, except: [:Frontend]))
          .not_to eq(machine_digest)
      end
    end

    context 'when a constant of an inner module differs' do
      it 'differs' do
        expect(described_class.of(ConstantSamples::MachineWithOtherPeriods, except: [:Frontend]))
          .not_to eq(machine_digest)
      end
    end

    context 'when a constant differs only inside a module left out' do
      it 'is the same' do
        expect(described_class.of(ConstantSamples::MachineWithOtherKeys, except: [:Frontend])).to eq(machine_digest)
      end
    end

    context 'when the namespace has one constant more, and one naming itself' do
      it 'differs' do
        expect(described_class.of(ConstantSamples::MachineWithMoreConstants, except: [:Frontend]))
          .not_to eq(machine_digest)
      end
    end
  end
end
