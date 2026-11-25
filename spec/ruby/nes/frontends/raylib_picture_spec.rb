# frozen_string_literal: true

# The frame on the GPU (plan 32): each pixel's value (0-511, docs/architecture.md Frame buffer contract) uploaded as is,
# and its colour looked up by a fragment shader in a texture of Frontends::Palette's 512 colours, so the window shows
# the colours Frontends::Palette.rgb gives the same frame buffer. What it draws is read back from a render texture
# (RaylibCanvas); `#close` is a smoke test, raylib's unloading leaving nothing to observe. Skipped when the optional
# `frontends` group is not installed.
RSpec.describe 'Ruby::Nes::Frontends::RaylibPicture', frontend_library: 'ruby/nes/frontends/raylib_picture' do
  describe '.new' do
    before { RaylibCanvas.open }

    after { RaylibCanvas.close }

    context 'when the fragment shader does not compile' do
      it 'raises a ShaderError' do
        expect { Ruby::Nes::Frontends::RaylibPicture.new(fragment_shader: "#version 330\nvoid main() { nonsense }") }
          .to raise_error(Ruby::Nes::Frontends::RaylibPicture::ShaderError)
      end
    end

    context 'when the fragment shader compiles' do
      # It calls a function it declares but never defines: a call compiles against the declaration, and the linker
      # finds no definition, on every driver (an input no vertex shader writes links on Mesa).
      context 'but it does not link' do
        let(:unlinkable_shader) do
          <<~GLSL
            #version 330
            out vec4 finalColor;
            vec4 undefinedColour();
            void main() { finalColor = undefinedColour(); }
          GLSL
        end

        it 'raises a ShaderError' do
          expect { Ruby::Nes::Frontends::RaylibPicture.new(fragment_shader: unlinkable_shader) }
            .to raise_error(Ruby::Nes::Frontends::RaylibPicture::ShaderError)
        end
      end

      context 'and it links' do
        it 'opens' do
          picture = Ruby::Nes::Frontends::RaylibPicture.new

          expect(picture).to be_a(Ruby::Nes::Frontends::RaylibPicture)
        ensure
          picture&.close
        end
      end
    end
  end

  describe '#draw' do
    subject(:picture) { Ruby::Nes::Frontends::RaylibPicture.new }

    before do
      RaylibCanvas.open
      picture
    end

    after do
      picture.close
    ensure
      RaylibCanvas.close
    end

    # Frames of 256 × 240 pixels (Ppu::Picture), whose values wrap at the palette's 512 colours.
    context 'when the source is the whole frame' do
      let(:source) { Raylib::Rectangle.create(0, 0, 256, 240) }

      context 'and the destination is the same size' do
        let(:destination) { Raylib::Rectangle.create(0, 0, 256, 240) }

        context 'and the pixels are 0-255' do
          let(:frame_buffer) { Array.new(256 * 240) { |position| position % 256 } }

          it 'draws each pixel in the colour Palette.rgb gives it' do
            drawn = RaylibCanvas.rgb(256, 240) { picture.draw(frame_buffer, source, destination) }

            expect(drawn).to eq(Ruby::Nes::Frontends::Palette.rgb(frame_buffer))
          end
        end

        context 'and the pixels are 256-511' do
          let(:frame_buffer) { Array.new(256 * 240) { |position| 256 + (position % 256) } }

          it 'draws each pixel in the colour Palette.rgb gives it' do
            drawn = RaylibCanvas.rgb(256, 240) { picture.draw(frame_buffer, source, destination) }

            expect(drawn).to eq(Ruby::Nes::Frontends::Palette.rgb(frame_buffer))
          end
        end

        context 'and another frame was drawn before' do
          let(:earlier_frame_buffer) { Array.new(256 * 240, 0x16) }
          let(:frame_buffer) { Array.new(256 * 240, 0x2A) }

          before { RaylibCanvas.rgb(256, 240) { picture.draw(earlier_frame_buffer, source, destination) } }

          it "draws the new frame's colours" do
            drawn = RaylibCanvas.rgb(256, 240) { picture.draw(frame_buffer, source, destination) }

            expect(drawn).to eq(Ruby::Nes::Frontends::Palette.rgb(frame_buffer))
          end
        end
      end

      # Each pixel's value is its column plus its row; at twice the size, the drawn pixel (x, y) is the frame's pixel
      # (x / 2, y / 2).
      context 'and the destination is larger' do
        let(:destination) { Raylib::Rectangle.create(0, 0, 512, 480) }
        let(:frame_buffer) { Array.new(256 * 240) { |position| ((position % 256) + (position / 256)) % 512 } }
        let(:doubled_frame_buffer) do
          Array.new(512 * 480) { |position| (((position % 512) / 2) + (position / 512 / 2)) % 512 }
        end

        it 'draws each pixel as a block of its colour' do
          drawn = RaylibCanvas.rgb(512, 480) { picture.draw(frame_buffer, source, destination) }

          expect(drawn).to eq(Ruby::Nes::Frontends::Palette.rgb(doubled_frame_buffer))
        end
      end
    end

    # The viewport's overscan crop (Frontends::Viewport): rows 8-231, 224 rows. Each pixel's value is its column plus
    # its row.
    context 'when the source is part of the frame' do
      let(:source) { Raylib::Rectangle.create(0, 8, 256, 224) }
      let(:destination) { Raylib::Rectangle.create(0, 0, 256, 224) }
      let(:frame_buffer) { Array.new(256 * 240) { |position| ((position % 256) + (position / 256)) % 512 } }
      let(:cropped_frame_buffer) { Array.new(256 * 224) { |position| ((position % 256) + (position / 256) + 8) % 512 } }

      it 'draws only that part' do
        drawn = RaylibCanvas.rgb(256, 224) { picture.draw(frame_buffer, source, destination) }

        expect(drawn).to eq(Ruby::Nes::Frontends::Palette.rgb(cropped_frame_buffer))
      end
    end
  end

  describe '#close' do
    subject(:picture) { Ruby::Nes::Frontends::RaylibPicture.new }

    before { RaylibCanvas.open }

    after { RaylibCanvas.close }

    it 'releases the textures and the shader' do
      expect { picture.close }.not_to raise_error
    end
  end
end
