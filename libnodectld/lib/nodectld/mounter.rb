require 'fileutils'
require 'libosctl'
require 'nodectld/utils'
require 'nodectld/exceptions'
require 'nodectld/remote_client'
require 'nodectld/mount_reporter'
require 'pathname'
require 'yaml'

module NodeCtld
  # Mounter takes care of mounting and umounting local/remote
  # datasets/snapshots to VPS.
  class Mounter
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl
    include Utils::Pool
    include Utils::Vps

    class << self
      # Mount NFS shares on the host, ready to be bind-mounted to the VPS
      def prepare_vps_mounts(pool_fs, vps_id)
        # TODO:
        #  - some temp dir on the host where we'll be mounting NFS shares
        #  - mount only directories that are not already mounted

        mounter = new(pool_fs, vps_id)

        mounter.load_vps_mounts.each do |mnt|
          mounter.mount_to_host(mnt, false)
        end
      end

      # Mount all VPS local and remote mounts
      def mount_vps_mounts(pool_fs, vps_id, rootfs_path)
        # TODO:
        #  - mount all local and remote mounts that are available
        #  - register mounts in osctl
        #    osctl ct mounts register --fs --mountpoint --opts --type --no-automount
        #  - mount only directories that are mounted on the host... the unmounted
        #    ones should go to delayed mounter

        mounter = new(pool_fs, vps_id)

        mounter.load_vps_mounts.each do |mnt|
          mounter.bind_mount_to_vps(mnt, rootfs_path)
        end
      end

      def unmount_vps_mounts(pool_fs, vps_id, rootfs_path)
        # TODO: is this necessary? well, we need to take care of the NFS mounts
        # on the host when the VPS is stopped... but how/when?
      end
    end

    def initialize(pool_fs, vps_id)
      @pool_fs = pool_fs
      @vps_id = vps_id
      @failed_mounts = {}
    end

    # Bind-mount NFS shares from the host to the VPS
    def bind_mount_to_vps(mnt, rootfs_path)
      cmd, fs, dst, type, opts = bind_mount_to_vps_cmd(mnt, rootfs_path)

      # Check that the source is mounted
      if %w(dataset_remote snapshot_remote).include?(mnt['type']) \
         && !Pathname.new(fs).mountpoint?
        return
      end

      # Ensure the mountpoint exists
      Dir.chdir(rootfs_path)
      reldst = mnt['dst']
      reldst = reldst[1..-1] while reldst.start_with?('/')

      FileUtils.mkpath(reldst)

      # Mount it
      syscmd(cmd)

      # Register in osctl
      osctl(%i(ct mounts register), [@vps_id, mnt['dst']], {
        fs: fs,
        type: type,
        opts: opts,
        on_ct_start: true,
      })

      report_state(mnt, :mounted)
    end

    def bind_mount_to_vps_cmd(mnt, rootfs_path)
      dst = File.join(rootfs_path, mnt['dst'])
      type = 'none'
      opts = ['bind', mnt['mode']].join(',')

      src = case mnt['type']
      when 'dataset_local'
        "/#{mnt['pool_fs']}/#{mnt['dataset_name']}/private"

      when 'dataset_remote'
        pool_host_mountpoint(@pool_fs, mnt['id'])

      when 'snapshot_local'
        "/#{pool_mounted_snapshot(@pool_fs, mnt['snapshot_id'])}/private"

      when 'snapshot_remote'
        pool_host_mountpoint(@pool_fs, mnt['id'])

      else
        fail "unknown mount type '#{mnt['type']}'"
      end

      [
        "#{$CFG.get(:bin, :mount)} -t #{type} -o #{opts} #{src} #{dst}",
        src,
        dst,
        type,
        opts
      ]
    end

    # Add a new mount into a running container
    #
    # NFS and snapshot mounts are first mounted on the host via {#prepare_mount}
    # and then bind-mounted via osctl. Local dataset mounts are given to
    # osctl directly.
    def mount_after_start(mnt, oneshot)
      fail 'unable to mount to host' unless mount_to_host(mnt, oneshot)

      _cmd, src, dst, type, opts = bind_mount_to_vps_cmd(mnt, '/')

      osctl(%i(ct mounts register), [@vps_id, dst], {
        fs: src,
        type: type,
        opts: opts,
      })
      osctl(%i(ct mounts activate), [@vps_id, dst])

      report_state(mnt, :mounted)
    end

    def mount_to_host(mnt, oneshot)
      return true if !%w(dataset_remote snapshot_remote).include?(mnt['type'])

      dst = pool_host_mountpoint(@pool_fs, mnt['id'])
      counter = 0
      cmd = mount_to_host_cmd(mnt, dst)

      unless oneshot
        # Check if a parent mount did not fail
        @failed_mounts.each do |m_dst, m_level|
          if mnt['dst'].start_with?(m_dst)
            case m_level
            when 'skip'
              fail_mount(mnt)

            when 'mount_later'
              mount_later(mnt)
              fail_mount(mnt)

            else
              # nothing to do, as it cannot be fail_start nor wait_for_mount
            end

            return
          end
        end
      end

      # Create mountpoint
      Dir.mkdir(dst) unless Dir.exist?(dst)

      begin
        syscmd(cmd)
        return true

      rescue SystemCommandFailed => e
        if /is busy or already mounted/ =~ e.output
          log(:info, :mounter, 'Already mounted')

        else
          raise e if oneshot

          case mnt['on_start_fail']
          when 'skip'
            fail_mount(mnt)
            report_state(mnt, :skipped)
            return

          when 'mount_later'
            # state is set by mount_later
            mount_later(mnt)
            fail_mount(mnt)

          when 'fail_start'
            report_state(mnt, :unmounted)
            raise e

          when 'wait_for_mount'
            report_state(mnt, :waiting) if counter == 0
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

      false
    end

    def mount_to_host_cmd(mnt, dst)
      case mnt['type']
      when 'dataset_local', 'snapshot_local'
        fail 'programming error'

      when 'dataset_remote'
        "#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} -o#{mnt['mode']} "+
        "#{mnt['src_node_addr']}:/#{mnt['pool_fs']}/#{mnt['dataset_name']}/private #{dst}"

      when 'snapshot_remote'
        "#{$CFG.get(:bin, :mount)} #{mnt['mount_opts']} -o#{mnt['mode']} "+
        "#{mnt['src_node_addr']}:/#{pool_mounted_snapshot(mnt['pool_fs'], mnt['snapshot_id'])}/private #{dst}"

      else
        fail "unknown mount type '#{mnt['type']}'"
      end
    end

    def umount(mnt, keep_going: false)
      # Remove mount from the VPS
      begin
        osctl(%i(ct mounts del), [@vps_id, mnt['dst']])

      rescue SystemCommandFailed => e
        raise e unless keep_going
      end

      # Remove the mount from the host
      if %w(dataset_remote snapshot_remote snapshot_local).include?(mnt['type'])
        host_path = pool_host_mountpoint(@pool_fs, mnt['id'])

        if Dir.exist?(host_path)
          begin
            syscmd("umount -f \"#{host_path}\"")
            Dir.rmdir(host_path)

          rescue SystemCommandFailed => e
            raise e if !keep_going && (e.rc != 1 || /not mounted/ !~ e.output)
          end
        end
      end

      report_state(mnt, :unmounted)
    end

    def load_vps_mounts
      YAML.load_file(mounts_config)
    end

    protected
    def fail_mount(opts)
      @failed_mounts[File.join(opts['dst'], '/')] = opts['on_start_fail']
    end

    def mount_later(opts)
      log(:info, :mounter, 'Delaying mount')

      if NodeCtld::STANDALONE
        RemoteClient.send_or_not($CFG.get(:remote, :socket), :delayed_mount, {
          pool_fs: @pool_fs,
          vps_id: @vps_id,
          mount: opts,
        })

      else
        DelayedMounter.mount(@pool_fs, @vps_id, opts)
      end
    end

    def report_state(opts, state)
      if NodeCtld::STANDALONE
        RemoteClient.send_or_not($CFG.get(:remote, :socket), :mount_state, {
          vps_id: @vps_id,
          mount_id: opts['id'],
          state: state,
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
