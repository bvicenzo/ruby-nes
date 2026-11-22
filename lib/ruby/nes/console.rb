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
    # The board gets the CPU, the PPU and the register sync (plan 20, decision 1; plan 21, decisions 2 and 6).
    #
    # The two standard controllers answer $4016 and $4017 through Input::ControllerPorts (plan 15); `controllers` hands
    # them to the frontend, which sets the buttons held on each.
    #
    # The APU answers the rest of $4000-$4017 (plan 22): it gets the CPU as its clock and IRQ line, and the CPU bus for
    # the DMC's sample reads (plan 23), is caught up after every step like the PPU, and its reset writes $00 to $4015.
    # The CPU gets the register sync as its interrupt sync, so an NMI edge during BRK or the interrupt sequence is known
    # before the vector is picked (plan 22, decision 1).
    class Console
      attr_reader :cpu, :ppu, :apu, :cpu_bus, :ppu_bus, :controllers

      def initialize(cartridge, controllers: [Input::Controller.new, Input::Controller.new])
        mapper = Mappers.build(cartridge)
        @controllers = controllers.dup.freeze
        @ppu_bus = PpuBus.new(mapper:)
        @ppu = Ppu.new(bus: @ppu_bus)
        register_sync = PpuRegisterSync.new(ppu: @ppu)
        controller_ports = Input::ControllerPorts.new(first: controllers.first, second: controllers.last)
        @apu = Apu.new
        @cpu_bus = CpuBus.new(mapper:, ppu_registers: register_sync, apu_registers: @apu, controller_ports:)
        @cpu = Cpu.new(bus: @cpu_bus)
        @apu.memory = @cpu_bus
        wire_clock(register_sync)
        wire_board(mapper, register_sync)
        @ppu.nmi_input = @cpu
        reset
      end

      # One CPU step (an instruction, an interrupt sequence or a jammed tick), then the PPU and the APU catch up to its
      # end. Returns the cycles the CPU advanced, a DMC stall from the APU's catch-up included (plan 23).
      def step
        cycles_before = @cpu.cycles
        @cpu.step
        @ppu.catch_up(@cpu.cycles)
        @apu.catch_up(@cpu.cycles)
        @cpu.cycles - cycles_before
      end

      # Steps until the PPU wraps to the next frame (plan 12, decision 7); it stops within the first instruction of it.
      def run_frame
        frame_number = @ppu.frame_number
        step while @ppu.frame_number == frame_number
      end

      # The reset button: the CPU's, the PPU's and the APU's reset, then the PPU and the APU catch up the reset
      # sequence's cycles.
      def reset
        @cpu.reset
        @ppu.reset
        @apu.reset
        @ppu.catch_up(@cpu.cycles)
        @apu.catch_up(@cpu.cycles)
      end

      private

      # The register sync and the APU get the CPU as their clock, built after them; the CPU gets the register sync,
      # which catches the PPU up before an interrupt sequence picks its vector (plan 22, decision 1).
      def wire_clock(register_sync)
        register_sync.cpu = @cpu
        @apu.cpu = @cpu
        @cpu.interrupt_sync = register_sync
      end

      # The board gets the CPU as its clock and IRQ line, the PPU as A12's clock, and the register sync that catches the
      # PPU up before a register write (plan 20, decision 1; plan 21, decisions 2 and 6).
      def wire_board(mapper, register_sync)
        mapper.cpu = @cpu
        mapper.ppu = @ppu
        mapper.register_sync = register_sync
      end
    end
  end
end

require_relative 'console/ppu_register_sync'
