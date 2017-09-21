module VpsAdmind
  # Mounter takes care of mounting and umounting local/remote
  # datasets/snapshots to VPS.
  class Mounter
    include Utils::Log
    include Utils::System
    include Utils::Vps
    include Utils::Pool

    class << self
      def mount_all(vps_id, mounts, oneshot, mode: nil)
        mounter = new(vps_id)
        mounts.each { |mnt| mounter.mount(mnt, oneshot) }
      end

      def umount_all(vps_id, mounts, mode: nil)
        mounter = new(vps_id)
        mounts.each { |mnt| mounter.umount(mnt, keep_going: mode == :actionscript) }
      end
    end

    def initialize(vps_id)
      @vps_id = vps_id
      @failed_mounts = {}
    end

    def mount_cmd(mnt)
      dst = "#{ve_root}/#{mnt['dst']}"

      cmd = case mnt['type']
        when 'dataset_local'
          "#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} -o#{mnt['mode']} /#{mnt['pool_fs']}/#{mnt['dataset_name']}/private #{dst}"

        when 'dataset_remote'
          "#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} -o#{mnt['mode']} #{mnt['src_node_addr']}:/#{mnt['pool_fs']}/#{mnt['dataset_name']}/private #{dst}"

        when 'snapshot_local'
          "#{$CFG.get(:bin, :mount)} -t zfs #{mnt['pool_fs']}/#{mnt['dataset_name']}@#{mnt['snapshot']} #{dst}"

        when 'snapshot_remote'
          "#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} -o#{mnt['mode']} #{mnt['src_node_addr']}:/#{pool_mounted_snapshot(mnt['pool_fs'], mnt['snapshot_id'])}/private #{dst}"

        else
          fail "unknown mount type '#{mnt['type']}'"
      end

      [dst, cmd]
    end

    def mount(opts, oneshot)
      counter = 0
      dst, cmd = mount_cmd(opts)

      unless oneshot
        # Check if a parent mount did not fail
        @failed_mounts.each do |m_dst, m_level|
          if dst.start_with?(m_dst)
            case m_level
              when 'skip'
                fail_mount(opts)

              when 'mount_later'
                mount_later(opts)
                fail_mount(opts)

              else
                # nothing to do, as it cannot be fail_start nor wait_for_mount
            end

            return
          end
        end
      end

      create_dst(dst)

      begin
        syscmd(cmd)
        report_state(opts, :mounted)

      rescue CommandFailed => e
        if /is busy or already mounted/ =~ e.output
          log(:info, :mounter, 'Already mounted')

        else
          raise e if oneshot

          case opts['on_start_fail']
            when 'skip'
              fail_mount(opts)
              report_state(opts, :skipped)
              return

            when 'mount_later'
              # state is set by mount_later
              mount_later(opts)
              fail_mount(opts)

            when 'fail_start'
              report_state(opts, :unmounted)
              raise e

            when 'wait_for_mount'
              report_state(opts, :waiting) if counter == 0
              counter += 1
              wait = random_wait(counter)

              log(:warn, :mounter, "Mount failed, retrying in #{wait} seconds")
              sleep(wait)
              retry

            else
              fail "unsupported value of mount on_start_fail '#{mnt['on_start_fail']}'"
          end
        end
      end
    end

    def umount_cmd(mnt)
      dst = "#{ve_root}/#{mnt['dst']}"
      [dst, "#{$CFG.get(:bin, :umount)} #{mnt['umount_opts']} #{dst}"]
    end

    def umount(opts, keep_going: false)
      dst, cmd = umount_cmd(opts)

      if File.exists?(dst)
        begin
          syscmd(cmd)

        rescue CommandFailed => e
          raise e if !keep_going && (e.rc != 1 || /not mounted/ !~ e.output)
        end
      end

      report_state(opts, :unmounted)
    end

    protected
    def create_dst(dst)
      return if File.exists?(dst)
      FileUtils.mkpath(dst)

    rescue Errno::EEXIST
      # it means, that the folder is mounted but was removed on the other end
      syscmd("#{$CFG.get(:bin, :umount)} -f #{dst}")
    end

    def fail_mount(opts)
      @failed_mounts[File.join(opts['dst'], '/')] = opts['on_start_fail']
    end

    def mount_later(opts)
      log(:info, :mounter, 'Delaying mount')

      if VpsAdmind::STANDALONE
        RemoteClient.send_or_not($CFG.get(:remote, :socket), :delayed_mount, {
            :vps_id => @vps_id,
            :mount => opts
        })

      else
        DelayedMounter.mount(@vps_id, opts)
      end
    end

    def report_state(opts, state)
      if VpsAdmind::STANDALONE
        RemoteClient.send_or_not($CFG.get(:remote, :socket), :mount_state, {
            :vps_id => @vps_id,
            :mount_id => opts['id'],
            :state => state
        })

      else
        MountReporter.report(@vps_id, opts['id'], state)
      end
    end

    def random_wait(counter)
      base = 10 + counter * 5
      base = 60 if base > 60

      r = 10 + counter * 10
      r = 240 if r > 240

      base + rand(r)
    end
  end
end
