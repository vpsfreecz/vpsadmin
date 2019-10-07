require 'libosctl'

module NodeCtld
  class NfsServer
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::Pool

    attr_reader :name, :address

    # @param name [String]
    # @param address [String]
    def initialize(name, address)
      @name = name.to_s
      @address = address
    end

    def create!
      syscmd("osctl-exportfs server new --address #{address} #{name}")
    end

    def destroy
      syscmd("osctl-exportfs server del #{name}", valid_rcs: [1])
    end

    def destroy!
      syscmd("osctl-exportfs server del #{name}")
    end

    def start!
      syscmd("osctl-exportfs server start #{name}")
    end

    def stop!
      syscmd("osctl-exportfs server stop #{name}")
    end

    # @param dir [String]
    # @param as [String]
    # @param host [String]
    # @param options [String]
    def add_export(dir, as, host, options)
      args = [
        'osctl-exportfs', 'export', 'add',
        '--directory', dir,
        '--as', as,
        '--host', host,
        '--options', options,
        name,
      ]

      syscmd(args.join(' '))
    end

    # @param as [String]
    # @param host [String]
    def remove_export(as, host)
      args = [
        'osctl-exportfs', 'export', 'del',
        '--as', as,
        '--host', host,
        name,
      ]

      syscmd(args.join(' '))
    end

    # @param pool_fs [String]
    # @param dataset [String]
    # @param as [String]
    # @param host [String]
    # @param options [Hash]
    def add_filesystem_export(pool_fs, dataset, as, host, options)
      add_export(
        File.join('/', pool_fs, dataset, 'private'),
        as,
        host,
        build_options(options),
      )
    end

    # @param pool_fs [String]
    # @param snapshot_clone [String]
    # @param as [String]
    # @param host [String]
    # @param options [Hash]
    def add_snapshot_export(pool_fs, snapshot_clone, as, host, options)
      add_export(
        File.join('/', pool_mounted_clone(pool_fs, snapshot_clone), 'private'),
        as,
        host,
        build_options(options),
      )
    end

    protected
    def build_options(opts)
      result = []

      opts.map do |k, v|
        case k.to_s
        when 'rw'
          result << (v ? 'rw' : 'ro')
        when 'sync'
          result << (v ? 'sync' : 'async')
        when 'subtree_check'
          result << (v ? 'subtree_check' : 'no_subtree_check')
        when 'root_squash'
          result << (v ? 'root_squash' : 'no_root_squash')
        end
      end

      result.join(',')
    end
  end
end
