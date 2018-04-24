require 'thread'
require 'nodectld/mounter'
require 'nodectld/utils'
require 'yaml'

module NodeCtld
  class DelayedMounter
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::Pool
    include Utils::Vps
    include Utils::OsCtl

    class << self
      attr_accessor :instance

      def mount(*args)
        instance.register_mount(*args)
      end

      def unregister_vps(*args)
        instance.unregister_vps(*args)
      end

      def unregister_vps_mount(*args)
        instance.unregister_vps_mount(*args)
      end

      def change_mount(*args)
        instance.change_mount(*args)
      end
    end

    def initialize
      self.class.instance = self

      @mutex = Mutex.new

      # vps_id => [mounts]
      @mounts = {}
    end

    def start
      @thread = Thread.new do
        load_delayed_mounts

        loop do
          break if @stop

          synchronize { try_mounts }

          sleep(3*60)
        end
      end
    end

    def stop
      @stop = true
      @thread.join
    end

    def register_mount(pool_fs, vps_id, opts)
      opts.update({
        'mounted' => false,
        'dst_slash' => File.join(opts['dst'], '/'),
        'registered_at' => Time.now.to_i
      })

      synchronize do
        fail 'not supporting more than one pool' if !@pool_fs.nil? && @pool_fs != pool_fs
        @pool_fs ||= pool_fs
        @mounts[vps_id] ||= []

        if @mounts[vps_id].detect { |m| m['id'] == opts['id'] }
          log(
            :info,
            :delayed_mounter,
            "Mount #{opts['id']} of VPS #{vps_id} is already registered"
          )

        else
          @mounts[vps_id] << opts
          log(:info, :delayed_mounter, "Registered mount for VPS #{vps_id}: #{opts['dst']}")
          MountReporter.report(vps_id, opts['id'], :delayed)
        end
      end
    end

    def unregister_vps(vps_id)
      synchronize { @mounts.delete(vps_id) }
      log(:info, :delayed_mounter, "Unregistered VPS #{vps_id}")
    end

    def unregister_vps_mount(vps_id, mnt_id)
      synchronize do
        next unless @mounts[vps_id]
        i = @mounts[vps_id].index { |m| m['id'] == mnt_id }

        if i
          mnt = @mounts[vps_id].delete_at(i)
          log(
            :info,
            :delayed_mounter,
            "Unregistered mount #{mnt['dst']} of VPS #{vps_id}"
          )
        end
      end
    end

    def change_mount(vps_id, mnt)
      synchronize do
        next unless @mounts[vps_id]

        i = @mounts[vps_id].index { |m| m['id'] == mnt['id'] }
        next unless i

        case mnt['on_start_fail']
        when 'mount_later', 'fail_start', 'wait_for_mount'
          log(:debug, :delayed_mounter, "Keep mount #{mnt['dst']} of VPS #{vps_id}")

        when 'skip'
          log(:info, :delayed_mounter, "Skipping mount #{mnt['dst']} of VPS #{vps_id}")
          @mounts[vps_id].delete_at(i)
          MountReporter.report(vps_id, mnt['id'], :unmounted)

        else
          log(
            :critical,
            :delayed_mounter,
            "unsupported on_start_fail type '#{mnt['on_start_fail']}' for mount #{mnt['id']}"
          )
        end
      end
    end

    def mounts
      synchronize { yield(@mounts) }
    end

    protected
    def try_mounts
      @mounts.delete_if do |vps_id, mounts|
        mounter = Mounter.new(@pool_fs, vps_id)
        @vps_id = vps_id  # necessary for status to work

        if status == :running
          log(:info, :delayed_mounter, "Retrying mounts of VPS #{vps_id}")

        else
          log(:info, :delayed_mounter, "VPS #{vps_id} is not running, forgetting mounts")
          next(true)
        end

        mounts.delete_if do |mnt|
          parent_not_mounted = mounts.detect do |parent|
            mnt['dst'].start_with?(parent['dst_slash'])
          end

          if parent_not_mounted
            log(:debug, :delayed_mounter, "Parent of #{mnt['dst']} is not yet mounted")
            next
          end

          begin
            mounter.mount_after_start(mnt, true)
            mnt['mounted'] = true
            log(:info, :delayed_mounter, 'Mount succeeded')
            ret = true

          rescue SystemCommandFailed => e
            log(:info, :delayed_mounter, 'Mount failed')
            ret = false
          end

          ret
        end

        done = mounts.empty?
        log(:info, :delayed_mounter, "All mounts of VPS #{vps_id} are mounted") if done
        done
      end
    end

    def load_delayed_mounts
      vps_mounts = {}
      db = Db.new

      rs = db.prepared(
        "SELECT m.vps_id, m.id, p.filesystem
        FROM mounts m
        INNER JOIN vpses ON vpses.id = m.vps_id
        INNER JOIN dataset_in_pools dips ON dips.id = vpses.dataset_in_pool_id
        INNER JOIN pools p ON p.id = dips.pool_id
        WHERE vpses.node_id = ? AND m.current_state = 4",
        $CFG.get(:vpsadmin, :node_id)
      )

      rs.each do |row|
        if !@pool_fs.nil? && @pool_fs != row['filesystem']
          fail 'not supporting more than one pool'
        end

        @pool_fs ||= row['filesystem']

        vps_mounts[ row['vps_id'] ] ||= []
        vps_mounts[ row['vps_id'] ] << row['id']
      end

      db.close

      return if vps_mounts.empty?

      log(:info, :delayed_mounter, "Loading delayed mounts from the database")

      vps_mounts.each do |vps, mounts|
        mounts_file = mounts_config(vps_id: vps)

        unless File.exists?(mounts_file)
          log(:warn, :delayed_mounter, "'#{mounts_file}' does not exist")
          next
        end

        begin
          cfg_mounts = YAML.load_file(mounts_file)

        rescue Exception => e
          log(:critical, :delayed_mounter, "Failed to load '#{mounts_file}': #{e.message}")
          next
        end

        mounts.each do |mnt|
          opts = cfg_mounts.detect { |m| m['id'] == mnt }

          if opts
            register_mount(@pool_fs, vps, opts)

          else
            log(:warn, :delayed_mounter, "Mount #{mnt} not found")
          end
        end
      end
    end

    def synchronize
      @mutex.synchronize { yield }
    end
  end
end
