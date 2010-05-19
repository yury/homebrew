def check_for_stray_dylibs
  bad_dylibs = Dir['/usr/local/lib/*.dylib'].select { |f| File.file? f and not File.symlink? f }
  if bad_dylibs.length > 0
    puts "You have unbrewed dylibs in /usr/local/lib. These could cause build problems"
    puts "when building Homebrew formula. If you no longer need them, delete them:"
    puts
    puts *bad_dylibs.collect { |f| "    #{f}" }
    puts
  end
end

def check_for_x11
  unless File.exists? '/usr/X11/lib/libpng.dylib'
    puts <<-EOS.undent
      You don't have X11 installed as part of your Xcode installation.
      This isn't required for all formula. But it is expected by some.

    EOS
  end
end

def check_for_other_package_managers
  if macports_or_fink_installed?
    puts <<-EOS.undent
      You have Macports or Fink installed. This can cause trouble.
      You don't have to uninstall them, but you may like to try temporarily
      moving them away, eg.

        sudo mv /opt/local ~/macports

    EOS
  end
end

def check_gcc_versions
  gcc_42 = gcc_42_build
  gcc_40 = gcc_40_build

  if gcc_42 == nil
    puts <<-EOS.undent
      We couldn't detect gcc 4.2.x. Some formulas require this compiler.

    EOS
  elsif gcc_42 < RECOMMENDED_GCC_42
    puts <<-EOS.undent
      Your gcc 4.2.x version is older than the recommended version. It may be advisable
      to upgrade to the latest release of Xcode.

    EOS
  end

  if gcc_40 == nil
    puts <<-EOS.undent
      We couldn't detect gcc 4.0.x. Some formulas require this compiler.

    EOS
  elsif gcc_40 < RECOMMENDED_GCC_40
    puts <<-EOS.undent
      Your gcc 4.0.x version is older than the recommended version. It may be advisable
      to upgrade to the latest release of Xcode.

    EOS
  end
end

def check_share_locale
  # If PREFIX/share/locale already exists, "sudo make install" of
  # non-brew installed software may cause installation failures.
  locale = HOMEBREW_PREFIX+'share/locale'
  return unless locale.exist?

  cant_read = []

  locale.find do |d|
    next unless d.directory?
    cant_read << d unless d.writable?
  end

  cant_read.sort!
  if cant_read.length > 0
    puts <<-EOS.undent
    Some folders in #{locale} aren't writable.
    This can happen if you "sudo make install" software that isn't managed
    by Homebrew. If a brew tries to add locale information to one of these
    folders, then the install will fail during the link step.
    You should probably `chown` them:

    EOS
    puts *cant_read.collect { |f| "    #{f}" }
    puts
  end

end

def check_usr_bin_ruby
  if /^1\.9/.match RUBY_VERSION
    puts <<-EOS.undent
      Ruby version #{RUBY_VERSION} is unsupported.
      Homebrew is developed and tested on Ruby 1.8.x, and may not work correctly
      on Ruby 1.9.x. Patches are accepted as long as they don't break on 1.8.x.

    EOS
  end
end

def check_homebrew_prefix
  unless HOMEBREW_PREFIX.to_s == '/usr/local'
    puts <<-EOS.undent
      You can install Homebrew anywhere you want, but some brews may not work
      correctly if you're not installing to /usr/local.

    EOS
  end
end

def check_user_path
  seen_prefix_bin = false
  seen_prefix_sbin = false
  seen_usr_bin = false

  paths = ENV['PATH'].split(':').collect{|p| File.expand_path p}

  paths.each do |p|
    if p == '/usr/bin'
      seen_usr_bin = true
      unless seen_prefix_bin
        puts <<-EOS.undent
          /usr/bin is in your PATH before Homebrew's bin. This means that system-
          provided programs will be used before Homebrew-provided ones. This is an
          issue if you install, for instance, Python.

          Consider editing your .bashrc to put:
            #{HOMEBREW_PREFIX}/bin
          ahead of /usr/bin in your $PATH.

        EOS
      end
    end

    seen_prefix_bin  = true if p == "#{HOMEBREW_PREFIX}/bin"
    seen_prefix_sbin = true if p == "#{HOMEBREW_PREFIX}/sbin"
  end

  unless seen_prefix_bin
    puts <<-EOS.undent
      Homebrew's bin was not found in your path. Some brews depend
      on other brews that install tools to bin.

      You should edit your .bashrc to add:
        #{HOMEBREW_PREFIX}/bin
      to $PATH.

      EOS
  end

  unless seen_prefix_sbin
    puts <<-EOS.undent
      Some brews install binaries to sbin instead of bin, but Homebrew's
      sbin was not found in your path.

      Consider editing your .bashrc to add:
        #{HOMEBREW_PREFIX}/sbin
      to $PATH.

      EOS
  end
end

def check_which_pkg_config
  binary = `which pkg-config`.chomp
  return if binary.empty?

  unless binary == "#{HOMEBREW_PREFIX}/bin/pkg-config"
    puts <<-EOS.undent
      You have a non-brew 'pkg-config' in your PATH:
        #{binary}

      `./configure` may have problems finding brew-installed packages using
      this other pkg-config.

    EOS
  end
end

def check_pkg_config_paths
  binary = `which pkg-config`.chomp
  return if binary.empty?

  # Use the debug output to determine which paths are searched
  pkg_config_paths = []

  debug_output = `pkg-config --debug 2>&1`
  debug_output.split("\n").each do |line|
    line =~ /Scanning directory '(.*)'/
    pkg_config_paths << $1 if $1
  end

  # Check that all expected paths are being searched
  unless pkg_config_paths.include? "/usr/X11/lib/pkgconfig"
    puts <<-EOS.undent
      Your pkg-config is not checking "/usr/X11/lib/pkgconfig" for packages.
      Earlier versions of the pkg-config formula did not add this path
      to the search path, which means that other formula may not be able
      to find certain dependencies.

      To resolve this issue, re-brew pkg-config with:
        brew rm pkg-config && brew install pkg-config
    EOS
  end
end

def check_for_gettext
  if File.exist? "#{HOMEBREW_PREFIX}/lib/libgettextlib.dylib" or
     File.exist? "#{HOMEBREW_PREFIX}/lib/libintl.dylib"
    puts <<-EOS.undent
      gettext was detected in your PREFIX.

      The gettext provided by Homebrew is "keg-only", meaning it does not
      get linked into your PREFIX by default.

      If you `brew link gettext` then a large number of brews that don't
      otherwise have a `depends_on 'gettext'` will pick up gettext anyway
      during the `./configure` step.
    EOS
  end
end

def brew_doctor
  read, write = IO.pipe

  if fork == nil
    read.close
    $stdout.reopen write
    
    check_usr_bin_ruby
    check_homebrew_prefix
    check_for_stray_dylibs
    check_gcc_versions
    check_for_other_package_managers
    check_for_x11
    check_share_locale
    check_user_path
    check_which_pkg_config
    check_pkg_config_paths
    check_for_gettext

    exit! 0
  else
    write.close

    unless (out = read.read).chomp.empty?
      puts out
    else
      puts "Your OS X is ripe for brewing. Any troubles you may be experiencing are"
      puts "likely purely psychosomatic."
    end
  end
end
