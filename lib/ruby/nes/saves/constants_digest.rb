# frozen_string_literal: true

require 'digest'

module Ruby
  module Nes
    module Saves
      # The values of a namespace's constants as one digest (plan 35, decision 2): a save state carries the tables the
      # console points at (a waveform, a frame counter's steps) by value, so a state saved before a change to one is
      # refused rather than run on the old table. Every constant of the namespace and of the modules defined inside it,
      # named relative to it so two namespaces compare, as `inspect` writes it: Marshal cannot write every constant (an
      # Enumerator::ArithmeticSequence), and the core's `inspect`s hold no memory address. The top-level modules named
      # in `except` (the frontends) are left out. Off the hot path: about 3 ms for the core, once per game.
      module ConstantsDigest
        # The SHA-256, hexadecimal, of the lines "relative name = value" of every constant under `namespace`, sorted.
        def self.of(namespace, except:)
          lines = []
          describe(namespace, namespace.name, except, lines)
          Digest::SHA256.hexdigest(lines.sort.join("\n"))
        end

        def self.describe(namespace, root_name, except, lines)
          namespace.constants(false).each do |name|
            next if except.include?(name)

            value = namespace.const_get(name, false)
            if value.is_a?(Module)
              describe(value, root_name, [], lines) if inner?(value, namespace)
            else
              lines << "#{namespace.name.delete_prefix(root_name)}::#{name} = #{value.inspect}"
            end
          end
        end

        # A module defined inside `namespace`, not one a constant only names (the namespace itself, another module).
        def self.inner?(value, namespace) = value.name.start_with?("#{namespace.name}::")

        private_class_method :describe, :inner?
      end
    end
  end
end
