#!/usr/bin/env ruby
#
# usage: ./preview.rb FILENAME[:LINE][:IGNORED]

require 'open3'
require 'shellwords'

COMMAND = ENV.fetch(
  'FZF_PREVIEW_COMMAND',
  %[bat --style=numbers --color=always {} || highlight -O ansi -l {} || coderay {} || rougify {} || cat {}]
)
ANSI    = /\x1b\[[0-9;]*m/
REVERSE = "\x1b[7m"
RESET   = "\x1b[m"

def usage
  puts "usage: #$0 FILENAME[:LINENO][:IGNORED]"
  exit 1
end

usage if ARGV.empty?

file, center, extra = ARGV.first.split(':')
if ARGV.first =~ /^[A-Z]:\\/
  file << ':' + center
  center = extra
end
usage unless file

path = File.expand_path(file)
unless File.readable? path
  puts "File not found: #{file}"
  exit 1
end

if `file --dereference --mime "#{file}"` =~ /binary/
  puts "#{file} is a binary file"
  exit 0
end

center = (center || 0).to_i
height =
  if ENV['LINES']
    ENV['LINES'].to_i
  else
    File.readable?('/dev/tty') ? `stty size < /dev/tty`.split.first.to_i : 40
  end
offset = [1, center - height / 3].max

Open3.popen3(COMMAND.gsub('{}', Shellwords.shellescape(path))) do |_in, out, _err|
  out.each_line.drop(offset - 1).take(height).each_with_index do |line, lno|
    if lno + offset == center
      puts REVERSE + line.chomp.gsub(ANSI) { |m| m + REVERSE } + RESET
    else
      puts line
    end
  end
end
print RESET
