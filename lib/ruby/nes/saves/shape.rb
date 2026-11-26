# frozen_string_literal: true

require 'digest'

module Ruby
  module Nes
    module Saves
      # The shape of an object graph (plan 35, decision 2): the classes of the objects reached from it and the instance
      # variables each holds, whatever their values. A save state records the console's, and is loaded only into a
      # console of the same shape: code that added a variable would find it nil in an older state, and one that renamed
      # a class could not load it. Objects are reached through instance variables, array elements and hash values;
      # integers, floats, strings, symbols, nil, true and false are values, not shape. The console's shape does not
      # change as it runs: every object is built at power-up (docs/architecture.md, Hot paths). Off the hot path: about
      # 5 ms for a console.
      module Shape
        # The SHA-256, hexadecimal, of the sorted distinct lines "class: sorted instance variable names" of every object
        # reached from `root`.
        def self.digest(root)
          Digest::SHA256.hexdigest(descriptions(root).sort.join("\n"))
        end

        def self.descriptions(root)
          reached = {}.compare_by_identity
          descriptions = {}
          pending = [root]
          until pending.empty?
            object = pending.pop
            next if scalar?(object) || reached.has_key?(object)

            reached[object] = true
            pending.concat(contents(object))
            descriptions[description(object)] = true unless object.is_a?(Array) || object.is_a?(Hash)
          end
          descriptions.keys
        end

        def self.scalar?(object)
          case object
          when Integer, Float, String, Symbol, nil, true, false then true
          else false
          end
        end

        def self.contents(object)
          case object
          when Array then object
          when Hash then object.values
          else object.instance_variables.map { object.instance_variable_get(it) }
          end
        end

        def self.description(object) = "#{object.class}: #{object.instance_variables.sort.join(' ')}"

        private_class_method :descriptions, :scalar?, :contents, :description
      end
    end
  end
end
