module VpsAdmind
  IMPLICIT_CONFIG = {
      :db => {
          :hosts => [],
          :user => nil,
          :pass => nil,
          :name => nil,
          :retry_interval => 30,
          :ssl => false,
          :connect_timeout => 15,
          :read_timeout => 15,
          :write_timeout => 15,
      },

      :vpsadmin => {
          :server_id => nil,
          :domain => "vpsfree.cz",
          :node_addr => nil, # loaded from db
          :netdev => "eth0", # loaded from db
          :max_tx => nil, # loaded from db
          :max_rx => nil, # loaded from db
          :queues => {
              :general => {
                  :threads => 6,
                  :urgent => 6,
                  :start_delay => 0
              },
              :storage => {
                  :threads => 2,
                  :urgent => 2,
                  :start_delay => 0
              },
              :network => {
                  :threads => 1,
                  :urgent => 0,
                  :start_delay => 0
              },
              :vps => {
                  :threads => 4,
                  :urgent => 4,
                  :start_delay => 0
              },
              :zfs_send => {
                  :threads => 1,
                  :urgent => 0,
                  :start_delay => 90*60,
              },
              :mail => {
                  :threads => 2,
                  :urgent => 2,
                  :start_delay => 0
              },
              :outage => {
                  :threads => 24,
                  :urgent => 0,
                  :start_delay => 0,
              },
              :queue => {
                  :threads => 8,
                  :urgent => 2,
                  :start_delay => 0,
              },
              :rollback => {
                  :threads => 6,
                  :urgent => 6,
                  :start_delay => 0,
              },
          },
          :queues_reservation_prune_interval => 60,
          :urgent_threads => 6,
          :check_interval => 1,
          :status_interval => 30,
          :status_log_interval => 900,
          :vps_status_interval => 120,
          :vps_status_log_interval => 3600,
          :storage_status_interval => 3600,
          :transfers_interval => 10,
          :update_vps_status => true,
          :track_transfers => true,
          :root => "/opt/vpsadmin/vpsadmind",
          :init => true,
          :type => nil, # loaded from db
          :mounts_dir => '/var/vpsadmin/mounts'
      },

      :vz => {
          :vzctl => "vzctl",
          :vzlist => "vzlist",
          :vzquota => "vzquota",
          :vzmigrate => "vzmigrate",
          :vz_root => "/vz",
          :vz_conf => "/etc/vz",
          :ve_private => "/vz/private/%{veid}", # loaded from db
      },

      :bin => {
          :cat => "cat",
          :df => "df",
          :rm => "rm",
          :mv => "mv",
          :cp => "cp",
          :mkdir => "mkdir",
          :rmdir => "rmdir",
          :chmod => "chmod",
          :tar => "tar",
          :scp => "scp",
          :rdiff_backup => "rdiff-backup",
          :rsync => "rsync",
          :iptables => "iptables",
          :ip6tables => "ip6tables",
          :git => "git",
          :zfs => "zfs",
          :mount => "mount",
          :umount => "umount",
          :uptime => "uptime",
          :uname => "uname",
          :hostname => "hostname",
          :ssh_keygen => "ssh-keygen",
          :exportfs => "exportfs",
          :tc => 'tc',
      },

      :vps => {
          :zfs => {
              :root_dataset => "vz/private",
              :sharenfs => nil,
          },
          :migration => {
              :dumpfile => "/vz/dump/Dump.%{veid}",
          },
          :stop_timeout => 5*60,
      },

      :node => {
          :pubkey => {
              :types => ['rsa', 'dsa'],
              :path => "/etc/ssh/ssh_host_%{type}_key.pub",
          },
          :known_hosts => "/root/.ssh/known_hosts",
      },

      :storage => {
          :update_status => true,
      },

      :mailer => {
          :smtp_server => "localhost",
          :smtp_port => 25,
      },

      :console => {
          :host => "localhost",
          :port => 8081,
      },

      :remote => {
          :socket => "/var/run/vpsadmind.sock",
      }
  }

  class AppConfig
    attr_reader :file

    def initialize(file)
      @file = file
      @mutex = Mutex.new
    end

    def load(db = true)
      begin
        tmp = YAML.load(File.read(@file))
      rescue ArgumentError
        $stderr.puts "Error loading config: #{$!.message}"
        return false
      end

      unless tmp
        $stderr.puts "Using implicit config, some specific settings (database, server id) are missing, may not work properly"
        @cfg = IMPLICIT_CONFIG
        return true
      end

      @cfg = merge(IMPLICIT_CONFIG, tmp)

      load_db_settings if db

      true
    end

    def load_db_settings
      db = Db.new(@cfg[:db])

      st = db.prepared_st(
          "SELECT role, ip_addr, net_interface, max_tx, max_rx FROM nodes WHERE id = ?",
          @cfg[:vpsadmin][:server_id]
      )
      rs = st.fetch

      unless rs
        $stderr.puts "Node is not registered in database!"
        return
      end

      @cfg[:vpsadmin][:type] = %i(node storage mailer)[ rs[0] ]
      @cfg[:vpsadmin][:node_addr] = rs[1]
      @cfg[:vpsadmin][:netdev] = rs[2]
      @cfg[:vpsadmin][:max_tx] = rs[3]
      @cfg[:vpsadmin][:max_rx] = rs[4]

      case @cfg[:vpsadmin][:type]
        when :node
          st = db.prepared_st(
              "SELECT ve_private FROM nodes WHERE id = ?",
              @cfg[:vpsadmin][:server_id]
          )
          rs = st.fetch

          if rs
            @cfg[:vz][:ve_private] = rs[0]
          else
            $stderr.puts "Failed to load settings from database"
          end

          st.close
      end

      db.close
    end

    def reload
      sync do
        load
      end
    end

    def get(*args)
      val = nil

      sync do
        args.each do |k|
          if val
            val = val[k]
          else
            val = @cfg[k]
          end
        end

        if block_given?
          yield(args.empty? ? @cfg : val)
          return

        elsif args.empty?
          val = @cfg
        end
      end

      val
    end

    def patch(what)
      sync do
        @cfg = merge(@cfg, what)
      end
    end

    def merge(src, override)
      src.merge(override) do |k, old_v, new_v|
        if old_v.instance_of?(Hash)
          next new_v if k == :handlers

          merge(old_v, new_v)
        else
          new_v
        end
      end
    end

    def sync
      @mutex.synchronize do
        yield
      end
    end
  end
end
