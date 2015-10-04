module VpsAdmind
  class DelayedMounter
    include Utils::Log
    include Utils::System
    include Utils::Vps
    include Utils::Vz

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
    end

    def initialize
      self.class.instance = self

      @mutex = Mutex.new

      # vps_id => [mounts]
      @mounts = {}
    end

    def start
      @thread = Thread.new do
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

    def register_mount(vps_id, opts)
      opts['mounted'] = false
      opts['dst_slash'] = File.join(opts['dst'], '/')

      synchronize do
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

    def mounts
      synchronize { yield(@mounts) }
    end

    protected
    def try_mounts
      @mounts.delete_if do |vps_id, mounts|
        mounter = Mounter.new(vps_id)
        @vps_id = vps_id  # necessary for status to work

        if status[:running]
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
            mounter.mount(mnt, true)
            mnt['mounted'] = true
            log(:info, :delayed_mounter, 'Mount succeeded')
            ret = true

          rescue CommandFailed => e
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

    def synchronize
      @mutex.synchronize { yield }
    end
  end
end
