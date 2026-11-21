# frozen_string_literal: true

# PPU registers (https://www.nesdev.org/wiki/PPU_registers) and the PPU's I/O latch
# (https://www.nesdev.org/wiki/Open_bus_behavior#PPU_open_bus): "Writes to any PPU port, including the nominally
# read-only status port at $2002, load a value onto the PPU's I/O bus"; "Reading a nominally "write-only" register
# returns the latch's current value, as do the unused bits of PPUSTATUS"; "Reading the PPU's status port loads a value
# onto bits 7-5 of the bus, leaving the rest unchanged"; "Reading a value from $2004 or $2007 loads a byte [...] onto
# this bus". PPUSTATUS: "Reading this register has the side effect of clearing the PPU's internal w register"; its bit 7
# is the VBlank flag, bit 6 the "Sprite 0 hit flag" and bit 5 the "Sprite overflow flag", both "cleared on dot 1 of the
# prerender scanline" and left by the read (plan 14). PPUCTRL bit 7 enables NMI; bit 3 picks the 8×8 sprites' pattern
# table, bit 5 the "Sprite size (0: 8x8 pixels; 1: 8x16 pixels)". PPUMASK bits 3-4 show the background and the
# sprites, "rendering" for the frame timing, bits 1-2 their leftmost 8 columns. OAMDATA writes "during rendering [...]
# do not modify values in OAM, but do perform a glitchy increment of OAMADDR"; "For emulation purposes, it is probably
# best to completely ignore writes during rendering" (plan 14, decision 4): they only load the latch.
#
# Reset (https://www.nesdev.org/wiki/PPU_power_up_state): the reset signal clears PPUCTRL, PPUMASK, PPUSCROLL, PPUADDR,
# their latch and the PPUDATA read buffer; "Note that the VRAM address itself (V) is _not_ cleared"; "The VBL flag
# (PPUSTATUS bit 7) is random at power, and unchanged by reset"; OAMADDR is unchanged. The signal is "cleared at the end
# of VBlank", and until then writes to PPUCTRL, PPUMASK, PPUSCROLL and PPUADDR have no effect ("Attempting to write to
# a register while it is being cleared has no effect"); by convention they still load the I/O latch, which is a bus,
# not one of the cleared registers: no source says either way (plan 12, decision 11).
#
# The clock (https://www.nesdev.org/wiki/Cycle_reference_chart): exactly 3 PPU dots per CPU cycle. An event raised while
# the frame timing advances belongs to the dot it enters, the dot from which a register read sees it. The CPU's edge
# detector "polls the status of the NMI line during φ2 of each CPU cycle (i.e., during the second half of each cycle)"
# (https://www.nesdev.org/wiki/CPU_interrupts): an NMI change on a cycle's first or middle dot is seen in that cycle,
# one on its last dot only in the next. That φ2 point, before the last dot, is calibrated with ppu_vbl_nmi 05-08,
# which pass only with it (plan 12, decision 2).
RSpec.describe Ruby::Nes::Ppu do
  describe '#cpu_write' do
    context 'when the PPU was reset and VBlank has not ended since' do
      subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

      let(:oam) { Ruby::Nes::Ppu::Oam.new }

      context 'and the address is $2000' do
        let(:bus) { instance_double(Ruby::Nes::PpuBus) }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }

        before do
          ppu.reset
          ppu.cpu_write(0x2000, 0x03)
        end

        it 'ignores the write' do
          expect(scroll_registers.temporary_address).to eq(0x0000)
        end

        it 'loads the byte into the latch' do
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x03)
        end
      end

      context 'and the address is $2001' do
        let(:bus) { instance_double(Ruby::Nes::PpuBus, place_address: nil) }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x3F00) }

        before do
          allow(bus).to receive(:read).with(0x3F00).and_return(0x2C)
          allow(bus).to receive(:read).with(0x2F00).and_return(0x00)
          ppu.reset
          ppu.cpu_write(0x2001, 0x01)
        end

        it 'ignores the write' do
          expect(ppu.cpu_read(0x2007, 0x00)).to eq(0x2C)
        end

        it 'loads the byte into the latch' do
          expect(ppu.cpu_read(0x2001, 0x00)).to eq(0x01)
        end
      end

      context 'and the address is $2005' do
        let(:bus) { instance_double(Ruby::Nes::PpuBus) }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }

        before do
          ppu.reset
          ppu.cpu_write(0x2005, 0x53)
        end

        it 'ignores the write' do
          expect(scroll_registers).to have_attributes(temporary_address: 0x0000, fine_x: 0, second_write?: false)
        end

        it 'loads the byte into the latch' do
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x53)
        end
      end

      context 'and the address is $2006' do
        let(:bus) { instance_double(Ruby::Nes::PpuBus) }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }

        before do
          ppu.reset
          ppu.cpu_write(0x2006, 0x21)
        end

        it 'ignores the write' do
          expect(scroll_registers).to have_attributes(temporary_address: 0x0000, second_write?: false)
        end

        it 'loads the byte into the latch' do
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x21)
        end
      end

      context 'and the address is $2003' do
        let(:bus) { instance_double(Ruby::Nes::PpuBus) }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }

        before do
          ppu.reset
          ppu.cpu_write(0x2003, 0x40)
        end

        it 'takes the write' do
          expect(oam.address).to eq(0x40)
        end
      end
    end

    context 'when writes are accepted' do
      context 'and the address is $2000' do
        subject(:ppu) do
          described_class.new(bus:, scroll_registers:, oam:, vertical_blank:, sprite_renderer:, renderer:)
        end

        let(:bus) { instance_double(Ruby::Nes::PpuBus, read: 0x00, place_address: nil) }
        let(:oam) { Ruby::Nes::Ppu::Oam.new }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }
        let(:vertical_blank) { instance_double(Ruby::Nes::Ppu::VerticalBlank, :nmi_enabled= => nil) }
        let(:sprite_renderer) do
          instance_double(Ruby::Nes::Ppu::SpriteRenderer, :pattern_table= => nil, :tall_sprites= => nil)
        end
        let(:renderer) { instance_double(Ruby::Nes::Ppu::Renderer, :pattern_table= => nil) }

        context 'and bits 1-0 select nametable 3' do
          before { ppu.cpu_write(0x2000, 0x03) }

          it 'places the select at t bits 11-10 and loads the byte into the latch', :aggregate_failures do
            expect(scroll_registers.temporary_address).to eq(0x0C00)
            expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x03)
          end
        end

        context 'and bit 2 is clear' do
          before { ppu.cpu_write(0x2000, 0x00) }

          it 'makes PPUDATA advance v by 1' do
            expect { ppu.cpu_read(0x2007, 0x00) }.to change(scroll_registers, :vram_address).to(0x2006)
          end
        end

        context 'and bit 2 is set' do
          before { ppu.cpu_write(0x2000, 0x04) }

          it 'makes PPUDATA advance v by 32' do
            expect { ppu.cpu_read(0x2007, 0x00) }.to change(scroll_registers, :vram_address).to(0x2025)
          end
        end

        context 'and bit 3 is clear' do
          before { ppu.cpu_write(0x2000, 0xF7) }

          it 'makes the 8×8 sprites use the pattern table at $0000' do
            expect(sprite_renderer).to have_received(:pattern_table=).with(0x0000)
          end
        end

        context 'and bit 3 is set' do
          before { ppu.cpu_write(0x2000, 0x08) }

          it 'makes the 8×8 sprites use the pattern table at $1000' do
            expect(sprite_renderer).to have_received(:pattern_table=).with(0x1000)
          end
        end

        context 'and bit 4 is clear' do
          before { ppu.cpu_write(0x2000, 0xEF) }

          it 'makes the background use the pattern table at $0000' do
            expect(renderer).to have_received(:pattern_table=).with(0x0000)
          end
        end

        context 'and bit 4 is set' do
          before { ppu.cpu_write(0x2000, 0x10) }

          it 'makes the background use the pattern table at $1000' do
            expect(renderer).to have_received(:pattern_table=).with(0x1000)
          end
        end

        context 'and bit 5 is clear' do
          before { ppu.cpu_write(0x2000, 0xDF) }

          it 'turns the 8×16 sprites off' do
            expect(sprite_renderer).to have_received(:tall_sprites=).with(false)
          end
        end

        context 'and bit 5 is set' do
          before { ppu.cpu_write(0x2000, 0x20) }

          it 'turns the 8×16 sprites on' do
            expect(sprite_renderer).to have_received(:tall_sprites=).with(true)
          end
        end

        context 'and bit 7 is clear' do
          before { ppu.cpu_write(0x2000, 0x7F) }

          it 'disables NMI' do
            expect(vertical_blank).to have_received(:nmi_enabled=).with(false)
          end
        end

        context 'and bit 7 is set' do
          before { ppu.cpu_write(0x2000, 0x80) }

          it 'enables NMI' do
            expect(vertical_blank).to have_received(:nmi_enabled=).with(true)
          end
        end
      end

      context 'and the address is $2001' do
        subject(:ppu) do
          described_class.new(bus:, scroll_registers:, oam:, frame_timing:, sprite_renderer:, renderer:)
        end

        let(:bus) { instance_double(Ruby::Nes::PpuBus, place_address: nil) }
        let(:oam) { Ruby::Nes::Ppu::Oam.new }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x3F00) }
        let(:sprite_renderer) do
          instance_double(Ruby::Nes::Ppu::SpriteRenderer, :enabled= => nil, :left_columns_shown= => nil)
        end
        let(:frame_timing) do
          instance_double(Ruby::Nes::Ppu::FrameTiming, :rendering_enabled= => nil, rendering_in_progress?: false)
        end
        let(:renderer) do
          instance_double(
            Ruby::Nes::Ppu::Renderer,
            :greyscale= => nil,
            :emphasis= => nil,
            :left_columns_shown= => nil,
            :background_enabled= => nil,
            :rendering_enabled= => nil
          )
        end

        context 'and bits 7-1 hold the other rendering settings' do
          before { ppu.cpu_write(0x2001, 0x1E) }

          it 'loads the byte into the latch' do
            expect(ppu.cpu_read(0x2001, 0x00)).to eq(0x1E)
          end
        end

        context 'and bit 0 is clear' do
          before do
            allow(bus).to receive(:read).with(0x3F00).and_return(0x2C)
            allow(bus).to receive(:read).with(0x2F00).and_return(0x00)
            ppu.cpu_write(0x2001, 0x18)
          end

          it 'makes palette reads keep the colour' do
            expect(ppu.cpu_read(0x2007, 0x00)).to eq(0x2C)
          end

          it 'turns greyscale off in the picture' do
            expect(renderer).to have_received(:greyscale=).with(false)
          end
        end

        context 'and bit 0 is set' do
          before do
            allow(bus).to receive(:read).with(0x3F00).and_return(0x2C)
            allow(bus).to receive(:read).with(0x2F00).and_return(0x00)
            ppu.cpu_write(0x2001, 0x01)
          end

          it "makes palette reads keep the colour's bits 5-4" do
            expect(ppu.cpu_read(0x2007, 0x00)).to eq(0x20)
          end

          it 'turns greyscale on in the picture' do
            expect(renderer).to have_received(:greyscale=).with(true)
          end
        end

        context 'and bit 1 is clear' do
          before { ppu.cpu_write(0x2001, 0xFD) }

          it 'hides the background in the leftmost 8 columns' do
            expect(renderer).to have_received(:left_columns_shown=).with(false)
          end
        end

        context 'and bit 1 is set' do
          before { ppu.cpu_write(0x2001, 0x02) }

          it 'shows the background in the leftmost 8 columns' do
            expect(renderer).to have_received(:left_columns_shown=).with(true)
          end
        end

        context 'and bit 2 is clear' do
          before { ppu.cpu_write(0x2001, 0xFB) }

          it 'hides the sprites in the leftmost 8 columns' do
            expect(sprite_renderer).to have_received(:left_columns_shown=).with(false)
          end
        end

        context 'and bit 2 is set' do
          before { ppu.cpu_write(0x2001, 0x04) }

          it 'shows the sprites in the leftmost 8 columns' do
            expect(sprite_renderer).to have_received(:left_columns_shown=).with(true)
          end
        end

        context 'and bits 4-3 are clear' do
          before { ppu.cpu_write(0x2001, 0xE7) }

          it 'disables rendering', :aggregate_failures do
            expect(frame_timing).to have_received(:rendering_enabled=).with(false)
            expect(renderer).to have_received(:rendering_enabled=).with(false)
          end

          it 'disables the background' do
            expect(renderer).to have_received(:background_enabled=).with(false)
          end

          it 'disables the sprites' do
            expect(sprite_renderer).to have_received(:enabled=).with(false)
          end
        end

        context 'and bit 3 is set' do
          before { ppu.cpu_write(0x2001, 0x08) }

          it 'enables rendering', :aggregate_failures do
            expect(frame_timing).to have_received(:rendering_enabled=).with(true)
            expect(renderer).to have_received(:rendering_enabled=).with(true)
          end

          it 'enables the background' do
            expect(renderer).to have_received(:background_enabled=).with(true)
          end

          it 'disables the sprites' do
            expect(sprite_renderer).to have_received(:enabled=).with(false)
          end
        end

        context 'and bit 4 is set' do
          before { ppu.cpu_write(0x2001, 0x10) }

          it 'enables rendering', :aggregate_failures do
            expect(frame_timing).to have_received(:rendering_enabled=).with(true)
            expect(renderer).to have_received(:rendering_enabled=).with(true)
          end

          it 'disables the background' do
            expect(renderer).to have_received(:background_enabled=).with(false)
          end

          it 'enables the sprites' do
            expect(sprite_renderer).to have_received(:enabled=).with(true)
          end
        end

        # PPUMASK bits 5-7: "Emphasize red", "Emphasize green", "Emphasize blue" on NTSC; the picture puts them in the
        # pixel (plan 16, decision 2).
        context 'and bits 7-5 are clear' do
          before { ppu.cpu_write(0x2001, 0x1F) }

          it 'emphasizes no colour' do
            expect(renderer).to have_received(:emphasis=).with(0x00)
          end
        end

        context 'and bits 7 and 5 are set' do
          before { ppu.cpu_write(0x2001, 0xBF) }

          it 'emphasizes red and blue' do
            expect(renderer).to have_received(:emphasis=).with(0xA0)
          end
        end
      end

      context 'and the address is $2002' do
        subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

        let(:bus) { instance_double(Ruby::Nes::PpuBus) }
        let(:oam) { Ruby::Nes::Ppu::Oam.new }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(temporary_address: 0x1234, second_write: true) }

        before { ppu.cpu_write(0x2002, 0x5A) }

        it 'only loads the latch', :aggregate_failures do
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x5A)
          expect(scroll_registers).to have_attributes(temporary_address: 0x1234, second_write?: true)
        end
      end

      context 'and the address is $2003' do
        subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

        let(:bus) { instance_double(Ruby::Nes::PpuBus) }
        let(:oam) { Ruby::Nes::Ppu::Oam.new }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }

        before { ppu.cpu_write(0x2003, 0x40) }

        it 'sets OAMADDR and loads the latch', :aggregate_failures do
          expect(oam.address).to eq(0x40)
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x40)
        end
      end

      context 'and the address is $2004' do
        subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:, frame_timing:) }

        let(:bus) { instance_double(Ruby::Nes::PpuBus) }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }
        let(:oam) { Ruby::Nes::Ppu::Oam.new(address: 0x40) }

        context 'but rendering is in progress' do
          let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, rendering_in_progress?: true) }

          before { ppu.cpu_write(0x2004, 0x7C) }

          it 'leaves OAM unchanged' do
            expect(oam.byte(0x40)).to eq(0x00)
          end

          it 'leaves OAMADDR unchanged' do
            expect(oam.address).to eq(0x40)
          end

          it 'loads the byte into the latch' do
            expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x7C)
          end
        end

        context 'and rendering is not in progress' do
          let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, rendering_in_progress?: false) }

          before { ppu.cpu_write(0x2004, 0x7C) }

          it 'writes the byte to OAM, moves OAMADDR and loads the latch', :aggregate_failures do
            expect(oam.byte(0x40)).to eq(0x7C)
            expect(oam.address).to eq(0x41)
            expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x7C)
          end
        end
      end

      context 'and the address is $2005' do
        subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

        let(:bus) { instance_double(Ruby::Nes::PpuBus) }
        let(:oam) { Ruby::Nes::Ppu::Oam.new }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }

        before { ppu.cpu_write(0x2005, 0x53) }

        it 'writes the scroll and loads the latch', :aggregate_failures do
          expect(scroll_registers).to have_attributes(temporary_address: 0x000A, fine_x: 0b011, second_write?: true)
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x53)
        end
      end

      # Outside rendering the PPU's bus shows v after each PPUADDR write: the first leaves v as it was, the second loads
      # it from t (plan 21, decision 10).
      context 'and the address is $2006' do
        context 'and it is the first write' do
          subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

          let(:bus) { instance_double(Ruby::Nes::PpuBus, place_address: nil) }
          let(:oam) { Ruby::Nes::Ppu::Oam.new }
          let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x1234) }

          before { ppu.cpu_write(0x2006, 0x21) }

          it 'writes the address and loads the latch', :aggregate_failures do
            expect(scroll_registers).to have_attributes(temporary_address: 0x2100, second_write?: true)
            expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x21)
          end

          it 'shows the unchanged v on its bus' do
            expect(bus).to have_received(:place_address).with(0x1234)
          end
        end

        context 'and it is the second write' do
          subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

          let(:bus) { instance_double(Ruby::Nes::PpuBus, place_address: nil) }
          let(:oam) { Ruby::Nes::Ppu::Oam.new }
          let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x1234) }

          before do
            ppu.cpu_write(0x2006, 0x10)
            ppu.cpu_write(0x2006, 0x08)
          end

          it 'shows the new v on its bus' do
            expect(bus).to have_received(:place_address).with(0x1008)
          end
        end
      end

      context 'and the address is $2007' do
        subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

        let(:bus) { instance_double(Ruby::Nes::PpuBus, write: nil, place_address: nil) }
        let(:oam) { Ruby::Nes::Ppu::Oam.new }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

        before { ppu.cpu_write(0x2007, 0x99) }

        it 'writes the byte at v and loads the latch', :aggregate_failures do
          expect(bus).to have_received(:write).with(0x2005, 0x99)
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x99)
        end
      end
    end
  end

  describe '#cpu_read' do
    context 'when the address is a write-only register' do
      subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }

      before { ppu.cpu_write(0x2002, 0x5A) }

      context 'and it is $2000' do
        it 'returns the latch, whatever is on the CPU data bus' do
          expect(ppu.cpu_read(0x2000, 0xFF)).to eq(0x5A)
        end
      end

      context 'and it is $2001' do
        it 'returns the latch, whatever is on the CPU data bus' do
          expect(ppu.cpu_read(0x2001, 0xFF)).to eq(0x5A)
        end
      end

      context 'and it is $2003' do
        it 'returns the latch, whatever is on the CPU data bus' do
          expect(ppu.cpu_read(0x2003, 0xFF)).to eq(0x5A)
        end
      end

      context 'and it is $2005' do
        it 'returns the latch, whatever is on the CPU data bus' do
          expect(ppu.cpu_read(0x2005, 0xFF)).to eq(0x5A)
        end
      end

      context 'and it is $2006' do
        it 'returns the latch, whatever is on the CPU data bus' do
          expect(ppu.cpu_read(0x2006, 0xFF)).to eq(0x5A)
        end
      end
    end

    context 'when the address is $2002' do
      subject(:ppu) do
        described_class.new(bus:, scroll_registers:, oam:, frame_timing:, vertical_blank:, sprite_status:)
      end

      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(second_write: true) }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }
      let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, status_read: nil) }

      context 'and the sprites overflowed and sprite 0 hit' do
        let(:vertical_blank) { instance_double(Ruby::Nes::Ppu::VerticalBlank, read: false) }
        let(:sprite_status) { Ruby::Nes::Ppu::SpriteStatus.new }

        before do
          sprite_status.overflow_found
          sprite_status.sprite_zero_hit
          ppu.cpu_write(0x2002, 0x00)
        end

        it 'returns bits 6-5 set' do
          expect(ppu.cpu_read(0x2002, 0x00)).to eq(0x60)
        end

        it 'leaves the sprite flags set' do
          expect { ppu.cpu_read(0x2002, 0x00) }.not_to change(sprite_status, :bits).from(0x60)
        end
      end

      context 'and the VBlank flag is clear' do
        let(:vertical_blank) { instance_double(Ruby::Nes::Ppu::VerticalBlank, read: false) }
        let(:sprite_status) { Ruby::Nes::Ppu::SpriteStatus.new }

        before { ppu.cpu_write(0x2002, 0xFF) }

        it 'returns bits 7-5 clear and bits 4-0 of the latch' do
          expect(ppu.cpu_read(0x2002, 0x00)).to eq(0x1F)
        end

        it 'clears w' do
          expect { ppu.cpu_read(0x2002, 0x00) }.to change(scroll_registers, :second_write?).from(true).to(false)
        end

        it 'loads its bits 7-5 into the latch and keeps bits 4-0' do
          ppu.cpu_read(0x2002, 0x00)
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x1F)
        end

        it 'tells the frame timing the status was read' do
          ppu.cpu_read(0x2002, 0x00)
          expect(frame_timing).to have_received(:status_read).once
        end
      end

      context 'and the VBlank flag is set' do
        let(:vertical_blank) { instance_double(Ruby::Nes::Ppu::VerticalBlank, read: true) }
        let(:sprite_status) { Ruby::Nes::Ppu::SpriteStatus.new }

        before { ppu.cpu_write(0x2002, 0x7F) }

        it 'returns bit 7 set, bits 6-5 clear and bits 4-0 of the latch' do
          expect(ppu.cpu_read(0x2002, 0x00)).to eq(0x9F)
        end

        it 'clears w' do
          expect { ppu.cpu_read(0x2002, 0x00) }.to change(scroll_registers, :second_write?).from(true).to(false)
        end

        it 'loads its bits 7-5 into the latch and keeps bits 4-0' do
          ppu.cpu_read(0x2002, 0x00)
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x9F)
        end

        it 'tells the frame timing the status was read' do
          ppu.cpu_read(0x2002, 0x00)
          expect(frame_timing).to have_received(:status_read).once
        end
      end
    end

    context 'when the address is $2004' do
      subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }
      let(:oam) { Ruby::Nes::Ppu::Oam.new(address: 0x40) }

      before do
        oam.write(0x7C)
        ppu.cpu_write(0x2003, 0x40)
      end

      it 'returns the OAM byte at OAMADDR and loads it into the latch', :aggregate_failures do
        expect(ppu.cpu_read(0x2004, 0x00)).to eq(0x7C)
        expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x7C)
      end
    end

    context 'when the address is $2007' do
      subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus, place_address: nil) }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }

      context 'and v is below the palette' do
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

        before do
          allow(bus).to receive(:read).with(0x2005).and_return(0x5A)
          allow(bus).to receive(:read).with(0x2006).and_return(0xA5)
          ppu.cpu_read(0x2007, 0x00)
        end

        it 'returns the buffered byte and loads it into the latch', :aggregate_failures do
          expect(ppu.cpu_read(0x2007, 0x00)).to eq(0x5A)
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x5A)
        end
      end

      context 'and v is in the palette' do
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x3F00) }

        before do
          allow(bus).to receive(:read).with(0x3F00).and_return(0x2C)
          allow(bus).to receive(:read).with(0x2F00).and_return(0x00)
          ppu.cpu_write(0x2002, 0xC0)
        end

        it "returns the colour with the latch's bits 7-6" do
          expect(ppu.cpu_read(0x2007, 0x00)).to eq(0xEC)
        end
      end
    end
  end

  describe '#reset' do
    subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:, frame_timing:, vertical_blank:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus, place_address: nil) }
    let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x3EFE) }
    let(:oam) { Ruby::Nes::Ppu::Oam.new }
    let(:frame_timing) do
      instance_double(
        Ruby::Nes::Ppu::FrameTiming, :rendering_enabled= => nil, reset: nil, rendering_in_progress?: false
      )
    end
    let(:vertical_blank) { instance_double(Ruby::Nes::Ppu::VerticalBlank, :nmi_enabled= => nil) }

    before do
      allow(bus).to receive(:read).and_return(0x2C)
      allow(bus).to receive(:read).with(0x3EFE).and_return(0x5A)
      ppu.cpu_read(0x2007, 0x00)
      ppu.cpu_write(0x2000, 0x84)
      ppu.cpu_write(0x2001, 0x19)
      ppu.cpu_write(0x2003, 0x40)
      ppu.cpu_write(0x2005, 0x53)
      ppu.reset
    end

    it 'disables NMI' do
      expect(vertical_blank).to have_received(:nmi_enabled=).with(false)
    end

    it 'makes PPUDATA advance v by 1' do
      expect { ppu.cpu_read(0x2007, 0x00) }.to change(scroll_registers, :vram_address).from(0x3EFF).to(0x3F00)
    end

    it 'turns greyscale off' do
      ppu.cpu_read(0x2007, 0x00)
      expect(ppu.cpu_read(0x2007, 0x00)).to eq(0x2C)
    end

    it 'disables rendering' do
      expect(frame_timing).to have_received(:rendering_enabled=).with(false)
    end

    it 'clears t, fine x and w' do
      expect(scroll_registers).to have_attributes(temporary_address: 0x0000, fine_x: 0, second_write?: false)
    end

    it 'clears the PPUDATA read buffer' do
      expect(ppu.cpu_read(0x2007, 0x00)).to eq(0x00)
    end

    it 'moves the frame timing to the top of an even frame' do
      expect(frame_timing).to have_received(:reset).once
    end

    it 'keeps OAMADDR' do
      expect(oam.address).to eq(0x40)
    end
  end

  describe '#vertical_blank_started' do
    subject(:ppu) { described_class.new(bus:, vertical_blank:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:vertical_blank) { instance_double(Ruby::Nes::Ppu::VerticalBlank, vertical_blank_started: nil) }

    before { ppu.vertical_blank_started }

    it 'tells the VBlank flag' do
      expect(vertical_blank).to have_received(:vertical_blank_started).once
    end
  end

  describe '#picture_completed' do
    subject(:ppu) { described_class.new(bus:, renderer:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:renderer) { instance_double(Ruby::Nes::Ppu::Renderer, complete_picture: nil) }

    before { ppu.picture_completed }

    it 'tells the renderer to complete the picture' do
      expect(renderer).to have_received(:complete_picture).once
    end
  end

  describe '#vertical_blank_ended' do
    context 'when the PPU was reset' do
      subject(:ppu) { described_class.new(bus:, scroll_registers:, frame_timing:, vertical_blank:, sprite_status:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }
      let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, :rendering_enabled= => nil, reset: nil) }
      let(:vertical_blank) do
        instance_double(Ruby::Nes::Ppu::VerticalBlank, :nmi_enabled= => nil, vertical_blank_ended: nil)
      end
      let(:sprite_status) { instance_double(Ruby::Nes::Ppu::SpriteStatus, clear: nil) }

      before do
        ppu.reset
        ppu.vertical_blank_ended
      end

      it 'tells the VBlank flag' do
        expect(vertical_blank).to have_received(:vertical_blank_ended).once
      end

      it 'clears the sprite flags' do
        expect(sprite_status).to have_received(:clear).once
      end

      it 'accepts writes to the registers again' do
        ppu.cpu_write(0x2000, 0x03)
        expect(scroll_registers.temporary_address).to eq(0x0C00)
      end
    end

    context 'when the PPU was not reset' do
      subject(:ppu) { described_class.new(bus:, vertical_blank:, sprite_status:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:vertical_blank) { instance_double(Ruby::Nes::Ppu::VerticalBlank, vertical_blank_ended: nil) }
      let(:sprite_status) { instance_double(Ruby::Nes::Ppu::SpriteStatus, clear: nil) }

      before { ppu.vertical_blank_ended }

      it 'tells the VBlank flag' do
        expect(vertical_blank).to have_received(:vertical_blank_ended).once
      end

      it 'clears the sprite flags' do
        expect(sprite_status).to have_received(:clear).once
      end
    end
  end

  describe '#nmi_output_changed' do
    context 'when no NMI input is wired' do
      subject(:ppu) { described_class.new(bus:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus) }

      it 'fails loudly' do
        expect { ppu.nmi_output_changed(true) }.to raise_error(NoMethodError)
      end
    end

    context 'when an NMI input is wired' do
      subject(:ppu) { described_class.new(bus:, nmi_input:, frame_timing:, renderer:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:nmi_input) { instance_double(Ruby::Nes::Cpu, nmi_line_changed: nil) }
      let(:renderer) { instance_double(Ruby::Nes::Ppu::Renderer, run_dot: nil) }

      context 'and the PPU stands between two CPU cycles' do
        let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, advance: nil, scanline: 0, dot: 0) }

        before { ppu.catch_up(10) }

        context 'and the output is asserted' do
          it 'tells the input on the CPU cycle that starts there' do
            ppu.nmi_output_changed(true)
            expect(nmi_input).to have_received(:nmi_line_changed).with(true, 10).once
          end
        end

        context 'and the output is released' do
          it 'tells the input on the CPU cycle that starts there' do
            ppu.nmi_output_changed(false)
            expect(nmi_input).to have_received(:nmi_line_changed).with(false, 10).once
          end
        end
      end

      context 'and the change comes as the PPU enters the middle dot of a CPU cycle' do
        let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, scanline: 0, dot: 0) }

        context 'and the output is asserted' do
          before do
            allow(frame_timing).to receive(:advance).and_invoke(-> { ppu.nmi_output_changed(true) }, -> {}, -> {})
          end

          it 'tells the input on the cycle of that dot' do
            ppu.catch_up(1)
            expect(nmi_input).to have_received(:nmi_line_changed).with(true, 0).once
          end
        end

        context 'and the output is released' do
          before do
            allow(frame_timing).to receive(:advance).and_invoke(-> { ppu.nmi_output_changed(false) }, -> {}, -> {})
          end

          it 'tells the input on the cycle of that dot' do
            ppu.catch_up(1)
            expect(nmi_input).to have_received(:nmi_line_changed).with(false, 0).once
          end
        end
      end

      context 'and the change comes as the PPU enters the last dot of a CPU cycle' do
        let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, scanline: 0, dot: 0) }

        context 'and the output is asserted' do
          before do
            allow(frame_timing).to receive(:advance).and_invoke(-> {}, -> { ppu.nmi_output_changed(true) }, -> {})
          end

          it 'tells the input on the next cycle, the first whose φ2 sees it' do
            ppu.catch_up(1)
            expect(nmi_input).to have_received(:nmi_line_changed).with(true, 1).once
          end
        end

        context 'and the output is released' do
          before do
            allow(frame_timing).to receive(:advance).and_invoke(-> {}, -> { ppu.nmi_output_changed(false) }, -> {})
          end

          it 'tells the input on the next cycle, the first whose φ2 sees it' do
            ppu.catch_up(1)
            expect(nmi_input).to have_received(:nmi_line_changed).with(false, 1).once
          end
        end
      end

      context 'and the change comes as the PPU enters the first dot of a CPU cycle' do
        let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, scanline: 0, dot: 0) }

        context 'and the output is asserted' do
          before do
            allow(frame_timing).to receive(:advance).and_invoke(-> {}, -> {}, -> { ppu.nmi_output_changed(true) })
          end

          it 'tells the input on the cycle of that dot' do
            ppu.catch_up(1)
            expect(nmi_input).to have_received(:nmi_line_changed).with(true, 1).once
          end
        end

        context 'and the output is released' do
          before do
            allow(frame_timing).to receive(:advance).and_invoke(-> {}, -> {}, -> { ppu.nmi_output_changed(false) })
          end

          it 'tells the input on the cycle of that dot' do
            ppu.catch_up(1)
            expect(nmi_input).to have_received(:nmi_line_changed).with(false, 1).once
          end
        end
      end
    end
  end

  describe '#catch_up' do
    subject(:ppu) { described_class.new(bus:, frame_timing:, renderer:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, advance: nil, scanline: 12, dot: 34) }
    let(:renderer) { instance_double(Ruby::Nes::Ppu::Renderer, run_dot: nil) }

    context 'when the CPU cycle is behind the PPU' do
      before do
        ppu.catch_up(10)
        ppu.catch_up(9)
      end

      it 'advances nothing' do
        expect(frame_timing).to have_received(:advance).exactly(30).times
      end
    end

    context "when the CPU cycle is the PPU's" do
      before do
        ppu.catch_up(10)
        ppu.catch_up(10)
      end

      it 'advances nothing' do
        expect(frame_timing).to have_received(:advance).exactly(30).times
      end
    end

    context 'when the CPU cycle is ahead of the PPU' do
      before do
        ppu.catch_up(10)
        ppu.catch_up(12)
      end

      it 'advances three dots per CPU cycle of difference' do
        expect(frame_timing).to have_received(:advance).exactly(36).times
      end

      it 'runs the renderer on each dot, where the frame timing stands' do
        expect(renderer).to have_received(:run_dot).with(12, 34).exactly(36).times
      end
    end
  end

  describe '#elapsed_dots' do
    subject(:ppu) { described_class.new(bus:, frame_timing:, renderer:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, advance: nil, scanline: 12, dot: 34) }
    let(:renderer) { instance_double(Ruby::Nes::Ppu::Renderer, run_dot: nil) }

    before do
      ppu.catch_up(10)
      ppu.catch_up(12)
    end

    it 'counts the dots run since the PPU was built' do
      expect(ppu.elapsed_dots).to eq(36)
    end
  end

  describe '#scanline' do
    subject(:ppu) { described_class.new(bus:, frame_timing:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, scanline: 241) }

    it "returns the frame timing's scanline" do
      expect(ppu.scanline).to eq(241)
    end
  end

  describe '#dot' do
    subject(:ppu) { described_class.new(bus:, frame_timing:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, dot: 21) }

    it "returns the frame timing's dot" do
      expect(ppu.dot).to eq(21)
    end
  end

  describe '#frame_number' do
    subject(:ppu) { described_class.new(bus:, frame_timing:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:frame_timing) { instance_double(Ruby::Nes::Ppu::FrameTiming, frame_number: 7) }

    it "returns the frame timing's frame number" do
      expect(ppu.frame_number).to eq(7)
    end
  end

  describe '#frame_buffer' do
    subject(:ppu) { described_class.new(bus:, renderer:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:renderer) { instance_double(Ruby::Nes::Ppu::Renderer, frame_buffer: [0x0F] * 4) }

    it 'is the last frame the renderer completed' do
      expect(ppu.frame_buffer).to eq([0x0F] * 4)
    end
  end
end
