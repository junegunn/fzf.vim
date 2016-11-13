#!/usr/bin/env ruby
#
# usage: ./preview.rb FILENAME LINENO VSPLIT(0|1)

require 'shellwords'

COMMAND = %[(highlight -O ansi -l {} || coderay {} || cat {}) 2> /dev/null]
ANSI    = /\x1b\[[0-9;]*m/
REVERSE = "\x1b[7m"
RESET   = "\x1b[m"

file, center, split = ARGV.fetch(0), ARGV.fetch(1).to_i, ARGV.fetch(2) == '1'
height = File.readable?('/dev/tty') ? `stty size < /dev/tty`.split.first.to_i : 40
height /= 2 if split
height -= 2 # preview border
offset = [1, center - height / 3].max

IO.popen(['sh', '-c', COMMAND.gsub('{}', Shellwords.shellescape(file))]) do |io|
  io.each_line.drop(offset - 1).take(height).each_with_index do |line, lno|
    if lno + offset == center
      puts REVERSE + line.chomp.gsub(ANSI) { |m| m + REVERSE } + RESET
    else
      puts line
    end
  end
end
