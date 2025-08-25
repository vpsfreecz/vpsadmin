require 'fileutils'
require 'libosctl'
require 'nodectld/utils'
require 'nodectld/exceptions'
require 'nodectld/remote_client'
require 'nodectld/mount_reporter'
require 'pathname'
require 'yaml'

module NodeCtld
  # Mounter takes care of mounting and umounting local datasets to VPS
  class Mounter
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl
    include Utils::Pool
    include Utils::Vps

    class << self
      # Mount all VPS local and remote mounts
      def mount_vps_mounts(pool_fs, vps_id, rootfs_path, map_mode, ns_pid)
        mounter = new(pool_fs, vps_id, map_mode:, ns_pid:)

        mounts = mounter.load_vps_mounts

        mounter.create_mountpoints(mounts, rootfs_path)

        mounts.each do |mnt|
          if mnt['type'] != 'dataset_local'
            log(:warn, "Ignoring mount ##{mnt['id']}: unsupported type #{mnt['type']}")
            next
          end

          mounter.bind_mount_to_vps(mnt, rootfs_path)
        end
      end
    end

    def initialize(pool_fs, vps_id, map_mode: nil, ns_pid: nil)
      @pool_fs = pool_fs
      @vps_id = vps_id
      @map_mode = map_mode
      @ns_pid = ns_pid
    end

    def create_mountpoints(mounts, rootfs_path)
      fork_chroot_wait(rootfs: rootfs_path) do
        if @map_mode == 'native'
          st = File.stat('/')

          Process.groups = [st.gid]
          sys = OsCtl::Lib::Sys.new
          sys.setresgid(st.uid, st.uid, st.uid)
          sys.setresuid(st.gid, st.gid, st.gid)
        end

        mounts.each do |mnt|
          FileUtils.mkpath(mnt['dst'])
        end
      end
    end

    # Bind-mount from the host to the VPS
    def bind_mount_to_vps(mnt, rootfs_path)
      cmd, fs, dst, type, opts = bind_mount_to_vps_cmd(mnt, rootfs_path)

      # Mount it
      syscmd(cmd)

      # Register in osctl
      osctl(%i[ct mounts register], [@vps_id, mnt['dst']], {
              fs:,
              type:,
              opts:,
              map_ids: true,
              on_ct_start: true
            })

      report_state(mnt, :mounted)
    end

    def bind_mount_to_vps_cmd(mnt, rootfs_path)
      dst = File.join(rootfs_path, mnt['dst'])
      type = 'none'

      use_opts = ['bind', mnt['mode']]
      ret_opts = use_opts.clone

      use_opts << "X-mount.idmap=/proc/#{@ns_pid}/ns/user" if @map_mode == 'native'

      src = case mnt['type']
            when 'dataset_local'
              "/#{mnt['pool_fs']}/#{mnt['dataset_name']}/private"

            else
              raise "unknown mount type '#{mnt['type']}'"
            end

      [
        "#{$CFG.get(:bin, :mount)} -t #{type} -o \"#{use_opts.join(',')}\" #{src} #{dst}",
        src,
        dst,
        type,
        ret_opts.join(',')
      ]
    end

    # Add a new mount into a running container
    def mount_after_start(mnt, _oneshot)
      _cmd, src, dst, type, opts = bind_mount_to_vps_cmd(mnt, '/')

      osctl(%i[ct mounts register], [@vps_id, dst], {
              fs: src,
              type:,
              opts:,
              map_ids: true
            })
      osctl(%i[ct mounts activate], [@vps_id, dst])

      report_state(mnt, :mounted)
    end

    def umount(mnt, keep_going: false)
      # Remove mount from the VPS
      begin
        osctl(%i[ct mounts del], [@vps_id, mnt['dst']])
      rescue SystemCommandFailed => e
        raise e unless keep_going
      end

      report_state(mnt, :unmounted)
    end

    def load_vps_mounts
      VpsConfig.open(@pool_fs, @vps_id) { |cfg| cfg.mounts.map(&:to_h) }
    end

    protected

    def report_state(opts, state)
      if NodeCtld::STANDALONE
        RemoteClient.send_or_not(RemoteControl::SOCKET, :mount_state, {
                                   vps_id: @vps_id,
                                   mount_id: opts['id'],
                                   state:
                                 })

      else
        MountReporter.report(@vps_id, opts['id'], state)
      end
    end
  end
end
