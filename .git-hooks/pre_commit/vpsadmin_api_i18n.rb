module Overcommit::Hook::PreCommit
  class VpsadminApiI18n < Base
    def run
      output = `cd api && env -u BUNDLE_BIN_PATH -u BUNDLE_GEMFILE -u BUNDLER_VERSION BUNDLE_GEMFILE=Gemfile BUNDLE_PATH=.gems bundle exec rake vpsadmin:i18n:health 2>&1`

      return :pass if $?.exitstatus == 0

      [:fail, output]
    end
  end
end
