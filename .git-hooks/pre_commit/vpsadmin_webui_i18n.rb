module Overcommit::Hook::PreCommit
  class VpsadminWebuiI18n < Base
    def run
      output = `webui/lang/scripts/locales-health 2>&1`
      return :pass if $?.exitstatus == 0

      [:fail, output]
    end
  end
end
