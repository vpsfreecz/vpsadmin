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
      def mount_vps_mounts(pool_fs, vps_id, rootfs_path)
        mounter = new(pool_fs, vps_id)

        mounter.load_vps_mounts.each do |mnt|
          if mnt['type'] != 'dataset_local'
            log(:warn, "Ignoring mount ##{mnt['id']}: unsupported type #{mnt['type']}")
            next
          end

          mounter.bind_mount_to_vps(mnt, rootfs_path)
        end
      end
    end

    def initialize(pool_fs, vps_id)
      @pool_fs = pool_fs
      @vps_id = vps_id
    end

    # Bind-mount from the host to the VPS
    def bind_mount_to_vps(mnt, rootfs_path)
      cmd, fs, dst, type, opts = bind_mount_to_vps_cmd(mnt, rootfs_path)

      # Ensure the mountpoint exists
      Dir.chdir(rootfs_path)
      reldst = mnt['dst']
      reldst = reldst[1..] while reldst.start_with?('/')

      FileUtils.mkpath(reldst)

      # Mount it
      syscmd(cmd)

      # Register in osctl
      osctl(%i[ct mounts register], [@vps_id, mnt['dst']], {
              fs:,
              type:,
              opts:,
              on_ct_start: true
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

            else
              raise "unknown mount type '#{mnt['type']}'"
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
    def mount_after_start(mnt, _oneshot)
      _cmd, src, dst, type, opts = bind_mount_to_vps_cmd(mnt, '/')

      osctl(%i[ct mounts register], [@vps_id, dst], {
              fs: src,
              type:,
              opts:
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
