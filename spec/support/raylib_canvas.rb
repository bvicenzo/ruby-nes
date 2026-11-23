# frozen_string_literal: true

# A hidden raylib window for specs that draw on the GPU, and what they draw read back from a render texture (plan 32),
# so it is compared without reading the screen after the buffers swap (undefined in OpenGL). Only for groups tagged
# `frontend_library:` (FrontendLibraries): it needs the optional raylib gem.
module RaylibCanvas
  WINDOW_WIDTH = 256
  WINDOW_HEIGHT = 240
  TITLE = 'ruby-nes spec'
  # LoadImageFromTexture gives a render texture's pixels as R8G8B8A8, its bottom row first (OpenGL's origin).
  READ_BACK_BYTES_PER_PIXEL = 4
  # Each read-back pixel's red, green and blue, its alpha skipped.
  RGB_OF_PIXEL = 'a3x'

  def self.open
    require 'ruby/nes/frontends/raylib'
    Ruby::Nes::Frontends::Raylib.load_library
    ::Raylib.SetTraceLogLevel(::Raylib::LOG_ERROR)
    ::Raylib.SetConfigFlags(::Raylib::FLAG_WINDOW_HIDDEN)
    ::Raylib.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE)
  end

  def self.close = ::Raylib.CloseWindow

  # The RGB bytes the block draws into a width × height render texture cleared to black, row by row from the top, as
  # Frontends::Palette.rgb lays a frame out.
  def self.rgb(width, height, &)
    target = ::Raylib.LoadRenderTexture(width, height)
    draw_into(target, &)
    top_down_rgb(read_back(target, width, height), width, height)
  ensure
    ::Raylib.UnloadRenderTexture(target) if target
  end

  def self.draw_into(target)
    ::Raylib.BeginTextureMode(target)
    ::Raylib.ClearBackground(::Raylib::BLACK)
    yield
  ensure
    ::Raylib.EndTextureMode
  end
  private_class_method :draw_into

  def self.read_back(target, width, height)
    image = ::Raylib.LoadImageFromTexture(target.texture)
    image[:data].read_bytes(width * height * READ_BACK_BYTES_PER_PIXEL)
  ensure
    ::Raylib.UnloadImage(image) if image
  end
  private_class_method :read_back

  def self.top_down_rgb(rgba, width, height)
    row_bytes = width * READ_BACK_BYTES_PER_PIXEL
    rgba.unpack("a#{row_bytes}" * height).reverse.join.unpack(RGB_OF_PIXEL * width * height).join
  end
  private_class_method :top_down_rgb
end
