require 'yaml'

module NodeCtld
  SECRET_CONFIG = '/var/secrets/nodectld-config'

  IMPLICIT_CONFIG = {
    db: {
      hosts: [],
      user: nil,
      pass: nil,
      name: nil,
      retry_interval: 30,
      ssl: false,
      connect_timeout: 15,
      read_timeout: 15,
      write_timeout: 15,
    },

    # Choose from predefined runtime configurations: standard or minimal
    #
    # Minimal mode is for nodes that do not manage VPS, nor storage, but are used
    # only for executing generic transactions, such as sending emails. Minimal
    # mode disables the kernel log parser, NFS exports, VPS and storage status
    # updates, etc.
    mode: 'standard',

    vpsadmin: {
      node_id: nil,
      domain: "vpsfree.cz",
      node_addr: nil, # loaded from db
      max_tx: nil, # loaded from db
      max_rx: nil, # loaded from db
      net_interfaces: [],
      queues: {
        general: {
            threads: 6,
            urgent: 6,
            start_delay: 0
        },
        storage: {
            threads: 2,
            urgent: 2,
            start_delay: 0
        },
        network: {
            threads: 1,
            urgent: 0,
            start_delay: 0
        },
        vps: {
            threads: 4,
            urgent: 4,
            start_delay: 0
        },
        zfs_send: {
            threads: 3,
            urgent: 0,
            start_delay: 90*60,
        },
        mail: {
            threads: 2,
            urgent: 2,
            start_delay: 0
        },
        outage: {
            threads: 24,
            urgent: 0,
            start_delay: 0,
        },
        queue: {
            threads: 128,
            urgent: 16,
            start_delay: 0,
        },
        rollback: {
            threads: 6,
            urgent: 6,
            start_delay: 0,
        },
      },
      queues_reservation_prune_interval: 60,
      check_interval: 1,
      status_interval: 30,
      status_log_interval: 900,
      vps_status_interval: 120,
      vps_status_log_interval: 3600,
      storage_status_interval: 3600,
      transfers_interval: 10,
      update_vps_status: true,
      track_transfers: true,
      type: nil, # loaded from db
      transaction_public_key: '/etc/vpsadmin/transaction.key',
    },

    bin: {
      cat: "cat",
      df: "df",
      rm: "rm",
      mv: "mv",
      cp: "cp",
      mkdir: "mkdir",
      rmdir: "rmdir",
      chmod: "chmod",
      tar: "tar",
      scp: "scp",
      rdiff_backup: "rdiff-backup",
      rsync: "rsync",
      iptables: "iptables",
      ip6tables: "ip6tables",
      git: "git",
      zfs: "zfs",
      mount: "mount",
      umount: "umount",
      uptime: "uptime",
      uname: "uname",
      hostname: "hostname",
      ssh_keygen: "ssh-keygen",
      exportfs: "exportfs",
      tc: 'tc',
    },

    node: {
      pubkey: {
        types: ['rsa', 'dsa'],
        path: "/etc/ssh/ssh_host_%{type}_key.pub",
      },
      known_hosts: "/root/.ssh/known_hosts",
    },

    storage: {
      update_status: true,
    },

    mailer: {
      smtp_server: "localhost",
      smtp_port: 25,
    },

    console: {
      host: "localhost",
      port: 8081,
    },

    kernel_log: {
      enable: true,
    },

    oom_reports: {
      enable: true,
      exclude_vps_ids: [],
    },

    exports: {
      enable: true,
    },

    mbuffer: {
      send: {
        block_size: '1M',
        buffer_size: '256M',
        timeout: 90*60,
      },
      receive: {
        block_size: '1M',
        buffer_size: '128M',
        start_writing_at: 60,
        timeout: 90*60,
      },
    },
  }

  class AppConfig
    attr_reader :file

    def initialize(file)
      @file = file
      @mutex = Mutex.new
    end

    def load(db = true)
      begin
        tmp = load_yaml(File.read(@file))
      rescue ArgumentError => e
        warn "Error loading config: #{e.message}"
        return false
      end

      unless tmp
        warn 'Using implicit config, some specific settings '+
             '(database, server id) are missing, may not work properly'
        @cfg = IMPLICIT_CONFIG
        return true
      end

      @cfg = merge(IMPLICIT_CONFIG, tmp)

      if File.exist?(SECRET_CONFIG)
        begin
          tmp = load_yaml(File.read(SECRET_CONFIG))
        rescue ArgumentError => e
          warn "Error loading secret config: #{e.message}"
          return false
        end

        @cfg = merge(@cfg, tmp)
      end

      case @cfg[:mode]
      when 'standard'
        # pass
      when 'minimal'
        @cfg = merge(@cfg, {
          vpsadmin: {
            track_transfers: false,
            update_vps_status: false,
          },
          storage: {
            update_status: false,
          },
          kernel_log: {enable: false},
          oom_reports: {enable: false},
          exports: {enable: false},
        })
      else
        warn "Unsupported runtime mode '#{@cfg[:mode]}'"
        return false
      end

      load_db_settings if db

      true
    end

    def load_db_settings
      db = Db.new(@cfg[:db])

      rs = db.prepared(
        'SELECT role, ip_addr, max_tx, max_rx FROM nodes WHERE id = ?',
        @cfg[:vpsadmin][:node_id]
      ).get

      unless rs
        warn 'Node is not registered in database!'
        return
      end

      @cfg[:vpsadmin][:type] = %i(node storage mailer)[ rs['role'] ]
      @cfg[:vpsadmin][:node_addr] = rs['ip_addr']
      @cfg[:vpsadmin][:max_tx] = rs['max_tx']
      @cfg[:vpsadmin][:max_rx] = rs['max_rx']

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

    def load_yaml(v)
      YAML.safe_load(v, permitted_classes: [Symbol])
    end

    def sync
      @mutex.synchronize do
        yield
      end
    end
  end
end
