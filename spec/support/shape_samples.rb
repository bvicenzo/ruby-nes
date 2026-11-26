# frozen_string_literal: true

# Objects whose instance variables a spec of Saves::Shape chooses: their names, set in the order given, and their
# values.
#
#   ShapeSamples::Node.new(buttons: 0, sprites: [ShapeSamples::Node.new(x: 4)])
#   ShapeSamples::Node.new(loop_through: :children) # @children is [the node itself], a cycle
module ShapeSamples
  class Node
    def initialize(loop_through: nil, **variables)
      variables.each { |name, value| instance_variable_set(:"@#{name}", value) }
      instance_variable_set(:"@#{loop_through}", [self]) if loop_through
    end
  end

  # A class of another name with the same variables as a Node.
  class OtherNode < Node; end
end
