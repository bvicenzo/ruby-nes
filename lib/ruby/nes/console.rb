# frozen_string_literal: true

module Ruby
  module Nes
    # The console: a cartridge's board, the CPU and the PPU wired together and run in step, the PPU 3 dots per CPU
    # cycle (https://www.nesdev.org/wiki/Cycle_reference_chart). The clock synchronises on register access (plan 12,
    # decision 1): the PPU catches up to the CPU before every access to its registers (PpuRegisterSync) and after every
    # step. The PPU's NMI output reaches the CPU with the cycle it changed on (plan 12, decision 2).
    #
    # Building it is the power-up (plan 12, decision 8): the CPU's and the PPU's reset, then the PPU catches up the 7
    # cycles of the reset sequence, so it stands 21 dots into scanline 0, as nestest.log's `PPU:  0, 21` at `CYC:7`.
    #
    # The board gets the CPU as its clock, as the register sync does (plan 20, decision 1).
    #
    # The two standard controllers answer $4016 and $4017 through Input::ControllerPorts (plan 15); `controllers` hands
    # them to the frontend, which sets the buttons held on each.
    class Console
      attr_reader :cpu, :ppu, :cpu_bus, :ppu_bus, :controllers

      def initialize(cartridge, controllers: [Input::Controller.new, Input::Controller.new])
        mapper = Mappers.build(cartridge)
        @controllers = controllers.dup.freeze
        @ppu_bus = PpuBus.new(mapper:)
        @ppu = Ppu.new(bus: @ppu_bus)
        register_sync = PpuRegisterSync.new(ppu: @ppu)
        controller_ports = Input::ControllerPorts.new(first: controllers.first, second: controllers.last)
        @cpu_bus = CpuBus.new(mapper:, ppu_registers: register_sync, controller_ports:)
        @cpu = Cpu.new(bus: @cpu_bus)
        register_sync.cpu = @cpu
        mapper.cpu = @cpu
        @ppu.nmi_input = @cpu
        reset
      end

      # One CPU step (an instruction, an interrupt sequence or a jammed tick), then the PPU catches up to its end.
      # Returns the cycles the step took.
      def step
        cycles = @cpu.step
        @ppu.catch_up(@cpu.cycles)
        cycles
      end

      # Steps until the PPU wraps to the next frame (plan 12, decision 7); it stops within the first instruction of it.
      def run_frame
        frame_number = @ppu.frame_number
        step while @ppu.frame_number == frame_number
      end

      # The reset button: the CPU's and the PPU's reset, then the PPU catches up the reset sequence's cycles.
      def reset
        @cpu.reset
        @ppu.reset
        @ppu.catch_up(@cpu.cycles)
      end
    end
  end
end

require_relative 'console/ppu_register_sync'
