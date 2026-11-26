# frozen_string_literal: true

# Namespaces of constants for the specs of Saves::ConstantsDigest: Machine, and copies of it that differ in one way
# each. Every one holds STEPS, a Unit module with PERIODS, and a Frontend module with KEYS.
module ConstantSamples
  module Machine
    STEPS = [0, 1, 2].freeze
    module Unit
      PERIODS = [4, 8].freeze
    end

    module Frontend
      KEYS = ['x'].freeze
    end
  end

  # Machine's constants, with the same names and values.
  module SameMachine
    STEPS = [0, 1, 2].freeze
    module Unit
      PERIODS = [4, 8].freeze
    end

    module Frontend
      KEYS = ['x'].freeze
    end
  end

  # Machine with a value of its own top level changed.
  module MachineWithOtherSteps
    STEPS = [0, 1, 3].freeze
    module Unit
      PERIODS = [4, 8].freeze
    end

    module Frontend
      KEYS = ['x'].freeze
    end
  end

  # Machine with a value inside its inner module changed.
  module MachineWithOtherPeriods
    STEPS = [0, 1, 2].freeze
    module Unit
      PERIODS = [4, 16].freeze
    end

    module Frontend
      KEYS = ['x'].freeze
    end
  end

  # Machine with a value inside Frontend changed.
  module MachineWithOtherKeys
    STEPS = [0, 1, 2].freeze
    module Unit
      PERIODS = [4, 8].freeze
    end

    module Frontend
      KEYS = ['z'].freeze
    end
  end

  # Machine with one constant more, and a constant naming the namespace itself.
  module MachineWithMoreConstants
    STEPS = [0, 1, 2].freeze
    LENGTH = 3
    ITSELF = self
    module Unit
      PERIODS = [4, 8].freeze
    end

    module Frontend
      KEYS = ['x'].freeze
    end
  end
end
