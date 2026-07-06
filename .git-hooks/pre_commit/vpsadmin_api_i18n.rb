module Overcommit::Hook::PreCommit
  class VpsadminApiI18n < Base
    def run
      command = [
        'cd api && env',
        '-u BUNDLE_BIN_PATH',
        '-u BUNDLE_GEMFILE',
        '-u BUNDLER_VERSION',
        '-u GEM_HOME',
        '-u GEM_PATH',
        '-u RUBYLIB',
        '-u RUBYOPT',
        'BUNDLE_GEMFILE=Gemfile',
        'BUNDLE_PATH=.gems',
        'bundle exec rake vpsadmin:i18n:health'
      ].join(' ')

      output =
        if defined?(Bundler)
          Bundler.with_unbundled_env { `#{command} 2>&1` }
        else
          `#{command} 2>&1`
        end

      return :pass if $?.exitstatus == 0

      [:fail, output]
    end
  end
end
