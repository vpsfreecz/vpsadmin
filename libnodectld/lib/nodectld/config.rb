require 'socket'
require 'yaml'

module NodeCtld
  SECRET_CONFIGS = [
    '/var/secrets/nodectld-config',
    '/var/secrets/nodectld*.yml',
  ]

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

    rabbitmq: {
      hosts: [],
      vhost: '/',
      username: nil,
      password: nil,
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
      node_name: nil,
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
        zfs_recv: {
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
            threads: 128,
            urgent: 0,
            start_delay: 0,
        },
        queue: {
            threads: 256,
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
      vps_status_interval: 120,
      veth_map_interval: 3600,
      update_vps_status: true,
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

    shaper: {
      enable: true,
    },

    traffic_accounting: {
      enable: true,
      update_interval: 10,
      log_interval: 60,
      batch_size: 50,
    },

    storage: {
      update_status: true,
      status_interval: 120,
      update_interval: 90,
      batch_size: 50,
      pool_status: true,
      pool_interval: 60,
    },

    mailer: {
      smtp_server: "localhost",
      smtp_port: 25,
      smtp_open_timeout: 15,
      smtp_read_timeout: 60,
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
      submit_interval: 60,
    },

    exports: {
      enable: true,
      parallel_start: 4,
      start_delay: 5,
    },

    route_check: {
      default_timeout: 300,
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

    exporter: {
      enable: true,
      metrics_dir: '/run/metrics',
      interval: 60,
    },

    osctl_exporter: {
      enable: true,
      url: 'http://localhost:9101/metrics',
      interval: 120,
      batch_size: 50,
    },

    vps_ssh_host_keys: {
      enable: true,
      update_vps_delay: 1,
      update_all_interval: 3600,
      default_schedule_delay: 15,
    },

    dataset_expander: {
      enable: true,
      min_avail_bytes: 512 * 1024 * 1024,
      min_avail_percent: 1,
      min_expand_bytes: 20 * 1024 * 1024 * 1024,
      min_expand_percent: 10,
    },

    rpc_client: {
      debug: false,
      soft_timeout: 15,
      hard_timeout: 900,
    }
  }

  class AppConfig
    attr_reader :file

    def initialize(file)
      @file = file
      @on_update = {}
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

      SECRET_CONFIGS.each do |pattern|
        Dir.glob(pattern).each do |secret_cfg|
          begin
            tmp = load_yaml(File.read(secret_cfg))
          rescue ArgumentError => e
            warn "Error loading secret config #{secret_cfg.inspect}: #{e.message}"
            return false
          end

          @cfg = merge(@cfg, tmp)
        end
      end

      case @cfg[:mode]
      when 'standard'
        # pass
      when 'minimal'
        @cfg = merge(@cfg, {
          vpsadmin: {
            update_vps_status: false,
          },
          storage: {
            update_status: false,
          },
          shaper: {enable: false},
          traffic_accounting: {enable: false},
          kernel_log: {enable: false},
          oom_reports: {enable: false},
          exports: {enable: false},
          osctl_exporter: {enable: false},
          vps_ssh_host_keys: {enable: false},
          dataset_expander: {enable: false},
        })
      else
        warn "Unsupported runtime mode '#{@cfg[:mode]}'"
        return false
      end

      if @cfg[:vpsadmin][:node_name].nil?
        host_parts = Socket.gethostname.split('.')

        if host_parts.length > 2
          @cfg[:vpsadmin][:node_name] = host_parts[0..1].join('.')
        end
      end

      load_db_settings if db

      true
    end

    def load_db_settings
      cfg =
        RpcClient.run do |rpc|
          rpc.get_node_config
        end

      if cfg.nil?
        warn 'Node is not registered!'
        return
      end

      @cfg[:vpsadmin][:type] = cfg['role'].to_sym
      @cfg[:vpsadmin][:node_addr] = cfg['ip_addr']
      @cfg[:vpsadmin][:max_tx] = cfg['max_tx']
      @cfg[:vpsadmin][:max_rx] = cfg['max_rx']

      nil
    end

    def reload
      sync do
        load
      end

      call_on_update
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

    def minimal?
      sync { @cfg[:mode] == 'minimal' }
    end

    def patch(what)
      sync do
        @cfg = merge(@cfg, what)
      end

      call_on_update
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
      YAML.safe_load(v, permitted_classes: [Symbol], symbolize_names: true)
    end

    def on_update(name, &block)
      @on_update[name] = block
    end

    def unregister_update(name)
      @on_update.delete(name)
    end

    def sync
      @mutex.synchronize do
        yield
      end
    end

    protected
    def call_on_update
      @on_update.each_value { |block| block.call }
    end
  end
end
