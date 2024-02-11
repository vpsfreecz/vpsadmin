require 'haveapi/cli'
require 'vpsadmin/client/version'

module VpsAdmin
  module CLI
    module Commands; end

    class Cli < HaveAPI::CLI::Cli
      def show_version
        puts "#{VpsAdmin::Client::VERSION} based on haveapi-client " +
             HaveAPI::Client::VERSION
      end
    end
  end
end

require 'vpsadmin/cli/stream_downloader'
require 'vpsadmin/cli/commands/base_download'
require 'vpsadmin/cli/commands/vps_remote_console'
require 'vpsadmin/cli/commands/vps_migrate_many'
require 'vpsadmin/cli/commands/snapshot_download'
require 'vpsadmin/cli/commands/snapshot_send'
require 'vpsadmin/cli/commands/backup_dataset'
require 'vpsadmin/cli/commands/backup_vps'
require 'vpsadmin/cli/commands/network_top'
