require 'haveapi/cli'

module VpsAdmin
  module CLI
    module Commands ; end

    class Cli < HaveAPI::CLI::Cli

    end
  end
end

require 'vpsadmin/cli/stream_downloader'
require 'vpsadmin/cli/commands/base_download'
require 'vpsadmin/cli/commands/vps_remote_console'
require 'vpsadmin/cli/commands/vps_migrate_many'
require 'vpsadmin/cli/commands/snapshot_download'
require 'vpsadmin/cli/commands/snapshot_send'
