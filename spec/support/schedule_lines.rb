# frozen_string_literal: true

# A scanline of Ppu::RenderSchedule step flags for a stand-in schedule: the steps given for each dot or range of dots,
# none elsewhere.
#
#   ScheduleLines.build(321 => RenderSchedule::RELOAD, 322..329 => RenderSchedule::SHIFT, 1 => RenderSchedule::PIXEL)
module ScheduleLines
  DOTS_PER_SCANLINE = Ruby::Nes::Ppu::RenderSchedule::DOTS_PER_SCANLINE

  def self.build(steps_by_dots)
    Array.new(DOTS_PER_SCANLINE) { |dot| steps_at(steps_by_dots, dot) }.freeze
  end

  def self.steps_at(steps_by_dots, dot)
    steps_by_dots.find { |dots, _steps| Array(dots).include?(dot) }&.last || 0
  end
end
