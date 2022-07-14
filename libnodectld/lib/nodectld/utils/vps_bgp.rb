require 'erb'
require 'fileutils'

module NodeCtld
  module Utils::VpsBgp
    include OsCtl::Lib::Utils::File

    def generate_peer_config
      FileUtils.mkdir_p(peer_dir_path)
      tpl_path = File.join(NodeCtld.root, 'templates/bgp/bird_protocol.erb')

      protocols = []

      case @protocol
      when 'ipv4'
        protocols << 4
      when 'ipv6'
        protocols << 6
      when 'ipv46'
        protocols << 4 << 6
      else
        raise "unknown protocol '#{@protocol}'"
      end

      priorities = @ip_addresses.map { |ip| ip['priority'] }.uniq

      @channels = protocols.to_h do |ip_v|
        prio_ips = priorities.to_h do |prio|
          ips = @ip_addresses.select { |ip| ip['ip_version'] == ip_v && ip['priority'] == prio }
          [prio, ips.any? ? ips : nil]
        end.compact

        [ip_v, prio_ips]
      end

      regenerate_file(peer_file_path, 0o644) do |new|
        tpl = ERB.new(File.read(tpl_path), trim_mode: '-')
        new.write(tpl.result(binding))
      end
    end

    def remove_peer_config
      unlink_if_exists(peer_file_path)
    end

    def backup_peer_config
      FileUtils.cp(peer_file_path, backup_file_path, preserve: true)
    end

    def restore_peer_config
      File.rename(backup_file_path, peer_file_path)
    end

    def prune_peer_backups
      Dir.glob("#{peer_file_path}.backup-chain-#{@command.chain_id}-transaction-*").each do |f|
        File.unlink(f)
      end
    end

    def peer_dir_path
      File.join('/', @pool_fs, path_to_pool_working_dir(:config), 'bird')
    end

    def peer_file_path
      File.join(peer_dir_path, "vps#{@vps_id}-peer#{@peer_id}.conf")
    end

    def backup_file_path
      "#{peer_file_path}.backup-chain-#{@command.chain_id}-transaction-#{@command.id}"
    end

    def peer_name
      "vps#{@vps_id}peer#{@peer_id}"
    end

    def priority_to_path_prepends(priority)
      case priority
      when 'no_priority', 'high_priority'
        0
      when 'normal_priority'
        2
      when 'low_priority'
        4
      else
        raise "invalid priority '#{priority}'"
      end
    end
  end
end
