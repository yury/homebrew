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
#
class RefreshBrew
  RESPOSITORY_URL  = 'git://github.com/mxcl/homebrew.git'
  CHECKOUT_COMMAND = 'git checkout -q master'
  UPDATE_COMMAND   = "git pull #{RESPOSITORY_URL} master"
  REVISION_COMMAND = 'git log -l -1 --pretty=format:%H 2> /dev/null'
  GIT_UP_TO_DATE   = 'Already up-to-date'
  
  formula_regexp   = 'Library/Formula/(.+?)\.rb'
  ADDED_FORMULA    = %r{^\s+create mode \d+ #{formula_regexp}$}
  UPDATED_FORMULA  = %r{^\s+#{formula_regexp}\s}
  
  attr_reader :added_formulae, :updated_formulae
  
  def initialize
    @added_formulae, @updated_formulae = [], []
  end
  
  # Performs an update of the homebrew source. Returns +true+ if a newer
  # version was available, +false+ if already up-to-date.
  def update_from_masterbrew!
    output = ''
    in_prefix do
      if File.directory? '.git'
        safe_system CHECKOUT_COMMAND
      else
        safe_system "git init"
      end
      output = execute(UPDATE_COMMAND)
    end

    output.split("\n").reverse.each do |line|
      case line
      when ADDED_FORMULA
        @added_formulae << $1
      when UPDATED_FORMULA
        @updated_formulae << $1 unless @added_formulae.include?($1)
      end
    end
    @added_formulae.sort!
    @updated_formulae.sort!
    
    output.strip != GIT_UP_TO_DATE
  end
  
  def pending_formulae_changes?
    !@updated_formulae.empty?
  end
  
  def current_revision
    in_prefix { execute(REVISION_COMMAND).strip }
  rescue
    'TAIL'
  end
  
  private
  
  def in_prefix
    Dir.chdir(HOMEBREW_REPOSITORY) { yield }
  end
  
  def execute(cmd)
    out = `#{cmd}`
    unless $?.success?
      puts out
      raise "Failed while executing #{cmd}"
    end
    ohai(cmd, out) if ARGV.verbose?
    out
  end
end
