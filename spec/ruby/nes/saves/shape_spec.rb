# frozen_string_literal: true

require 'ruby/nes/saves'

# The shape of a console (plan 35, decision 2): which classes its objects are of and which instance variables each
# holds, whatever their values. A save state records it, and a state is loaded only into a console of the same shape:
# code that added a variable would find it nil in an older state. Objects are reached through instance variables,
# array elements and hash values; integers, strings, symbols, floats, nil, true and false are values, not shape.
RSpec.describe Ruby::Nes::Saves::Shape do
  describe '.digest' do
    context 'when the two graphs hold objects of the same classes with the same instance variables' do
      context 'and their values differ' do
        let(:first_graph) { ShapeSamples::Node.new(buttons: 0x01, sprites: [ShapeSamples::Node.new(x: 4)]) }
        let(:second_graph) { ShapeSamples::Node.new(buttons: 0x80, sprites: [ShapeSamples::Node.new(x: 200)]) }

        it 'is the same' do
          expect(described_class.digest(first_graph)).to eq(described_class.digest(second_graph))
        end
      end

      context 'and the variables were set in another order' do
        let(:first_graph) { ShapeSamples::Node.new(buttons: 0x01, strobe: false) }
        let(:second_graph) { ShapeSamples::Node.new(strobe: false, buttons: 0x01) }

        it 'is the same' do
          expect(described_class.digest(first_graph)).to eq(described_class.digest(second_graph))
        end
      end
    end

    context 'when an object differs in its class' do
      let(:first_graph) { ShapeSamples::Node.new(channel: ShapeSamples::Node.new(timer: 0)) }
      let(:second_graph) { ShapeSamples::Node.new(channel: ShapeSamples::OtherNode.new(timer: 0)) }

      it 'differs' do
        expect(described_class.digest(first_graph)).not_to eq(described_class.digest(second_graph))
      end
    end

    context 'when an object has one instance variable more' do
      let(:first_graph) { ShapeSamples::Node.new(channel: ShapeSamples::Node.new(timer: 0)) }
      let(:second_graph) { ShapeSamples::Node.new(channel: ShapeSamples::Node.new(timer: 0, period: 0)) }

      it 'differs' do
        expect(described_class.digest(first_graph)).not_to eq(described_class.digest(second_graph))
      end
    end

    context 'when an object held in an array has one instance variable more' do
      let(:first_graph) { ShapeSamples::Node.new(channels: [0, ShapeSamples::Node.new(timer: 0)]) }
      let(:second_graph) { ShapeSamples::Node.new(channels: [0, ShapeSamples::Node.new(timer: 0, period: 0)]) }

      it 'differs' do
        expect(described_class.digest(first_graph)).not_to eq(described_class.digest(second_graph))
      end
    end

    context 'when an object held as a hash value has one instance variable more' do
      let(:first_graph) { ShapeSamples::Node.new(channels: { pulse: ShapeSamples::Node.new(timer: 0) }) }
      let(:second_graph) { ShapeSamples::Node.new(channels: { pulse: ShapeSamples::Node.new(timer: 0, period: 0) }) }

      it 'differs' do
        expect(described_class.digest(first_graph)).not_to eq(described_class.digest(second_graph))
      end
    end

    # The console's graph is full of cycles: the CPU holds its bus, which holds the devices, which hold the CPU.
    context 'when the graph holds a cycle' do
      let(:first_graph) { ShapeSamples::Node.new(loop_through: :children) }
      let(:second_graph) { ShapeSamples::Node.new(loop_through: :children) }

      it 'is the same for two graphs of the same shape' do
        expect(described_class.digest(first_graph)).to eq(described_class.digest(second_graph))
      end
    end
  end
end
