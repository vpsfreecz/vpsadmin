module Overcommit::Hook::PreCommit
  class MigrationSpecs < Base
    def run
      output = `tools/check_migration_specs.rb --cached 2>&1`
      return :pass if $?.exitstatus == 0

      [:fail, output]
    end
  end
end
