#  Copyright 2009 Max Howell and other contributors.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
#  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
#  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
#  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
#  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
#  NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
#  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

class Tty
  class <<self
    def blue; bold 34; end
    def white; bold 39; end
    def red; underline 31; end
    def yellow; underline 33 ; end
    def reset; escape 0; end
    def em; underline 39; end
    
  private
    def color n
      escape "0;#{n}"
    end
    def bold n
      escape "1;#{n}"
    end
    def underline n
      escape "4;#{n}"
    end
    def escape n
      "\033[#{n}m" if $stdout.tty?
    end
  end
end

# args are additional inputs to puts until a nil arg is encountered
def ohai title, *sput
  title = title.to_s[0, `/usr/bin/tput cols`.strip.to_i-4] unless ARGV.verbose?
  puts "#{Tty.blue}==>#{Tty.white} #{title}#{Tty.reset}"
  puts *sput unless sput.empty?
end

def opoo warning
  puts "#{Tty.red}Warning#{Tty.reset}: #{warning}"
end

def onoe error
  lines = error.to_s.split'\n'
  puts "#{Tty.red}Error#{Tty.reset}: #{lines.shift}"
  puts *lines unless lines.empty?
end

def pretty_duration s
  return "2 seconds" if s < 3 # avoids the plural problem ;)
  return "#{s.to_i} seconds" if s < 120
  return "%.1f minutes" % (s/60)
end

def interactive_shell
  fork do
    # TODO make the PS1 var change pls
    #brown="\[\033[0;33m\]"
    #reset="\[\033[0m\]"
    #ENV['PS1']="Homebrew-#{HOMEBREW_VERSION} #{brown}\W#{reset}\$ "
    exec ENV['SHELL']
  end
  Process.wait
  unless $?.success?
    puts "Aborting due to non-zero exit status"
    exit $?
  end
end

module Homebrew
  def self.system cmd, *args
    puts "#{cmd} #{args*' '}" if ARGV.verbose?
    fork do
      yield if block_given?
      args.collect!{|arg| arg.to_s}
      exec(cmd, *args) rescue nil
      exit! 1 # never gets here unless exec failed
    end
    Process.wait
    $?.success?
  end
end

# Kernel.system but with exceptions
def safe_system cmd, *args
  raise ExecutionError.new(cmd, args, $?) unless Homebrew.system(cmd, *args)
end

# prints no output
def quiet_system cmd, *args
  Homebrew.system(cmd, *args) do
    $stdout.close
    $stderr.close
  end
end

def curl *args
  safe_system 'curl', '-f#LA', HOMEBREW_USER_AGENT, *args unless args.empty?
end

def puts_columns items, cols = 4
  return if items.empty?

  if $stdout.tty?
    items = items.join("\n") if items.is_a?(Array)
    items.concat("\n") unless items.empty?

    # determine the best width to display for different console sizes
    console_width = `/bin/stty size`.chomp.split(" ").last.to_i
    console_width = 80 if console_width <= 0
    longest = items.sort_by { |item| item.length }.last
    optimal_col_width = (console_width.to_f / (longest.length + 2).to_f).floor
    cols = optimal_col_width > 1 ? optimal_col_width : 1

    IO.popen("/usr/bin/pr -#{cols} -t -w#{console_width}", "w"){|io| io.write(items) }
  else
    puts *items
  end
end

def exec_editor *args
  editor=ENV['EDITOR']
  if editor.nil?
    if system "/usr/bin/which -s mate"
      editor='mate'
    else
      editor='/usr/bin/vim'
    end
  end
  # we split the editor because especially on mac "mate -w" is common
  # but we still want to use the comma-delimited version of exec because then
  # we don't have to escape args, and escaping 100% is tricky
  exec *(editor.split+args)
end

# GZips the given path, and returns the gzipped file
def gzip path
  system "/usr/bin/gzip", path
  return Pathname.new(path+".gz")
end

# returns array of architectures suitable for -arch gcc flag
def archs_for_command cmd
    cmd = `/usr/bin/which #{cmd}` unless Pathname.new(cmd).absolute?
    cmd.gsub! ' ', '\\ '

    IO.popen("/usr/bin/file #{cmd}").readlines.inject(%w[]) do |archs, line|
      case line
      when /Mach-O executable ppc/
        archs << :ppc7400
      when /Mach-O 64-bit executable ppc64/
        archs << :ppc64
      when /Mach-O executable i386/
        archs << :i386
      when /Mach-O 64-bit executable x86_64/
        archs << :x86_64
      else
        archs
      end
    end
end

# String extensions added by inreplace below.
module HomebrewInreplaceExtension
  # Looks for Makefile style variable defintions and replaces the
  # value with "new_value", or removes the definition entirely.
  def change_make_var! flag, new_value
    new_value = "#{flag}=#{new_value}"
    gsub! Regexp.new("^#{flag}\\s*=\\s*(.*)$"), new_value
  end
  # Removes variable assignments completely.
  def remove_make_var! flags
    flags.each do |flag|
      # Also remove trailing \n, if present.
      gsub! Regexp.new("^#{flag}\\s*=(.*)$\n?"), ""
    end
  end
end

def inreplace path, before=nil, after=nil
  f = File.open(path, 'r')
  s = f.read

  if before == nil and after == nil
    s.extend(HomebrewInreplaceExtension)
    yield s
  else
    s.gsub!(before, after)
  end

  f.reopen(path, 'w').write(s)
  f.close
end

def ignore_interrupts
  std_trap = trap("INT") {}
  yield
ensure
  trap("INT", std_trap)
end

def nostdout
  if ARGV.verbose?
    yield
  else
    begin
      require 'stringio'
      real_stdout = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = real_stdout
    end
  end
end
