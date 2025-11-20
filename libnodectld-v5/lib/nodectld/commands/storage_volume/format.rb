module NodeCtld
  class Commands::StorageVolume::Format < Commands::Base
    handle 5231
    needs :system

    def exec
      @nbd_dev = NbdAllocator.get_device
      syscmd("qemu-nbd --connect #{@nbd_dev} #{vol_path}")
      syscmd("wipefs -a #{@nbd_dev}") if @wipe
      syscmd("mkfs.#{@filesystem} -L #{@label} #{@nbd_dev}")
      install_os_template if @os_template
      syscmd("qemu-nbd --disconnect #{@nbd_dev}")
      NbdAllocator.free_device(@nbd_dev)
      ok
    end

    def rollback
      if @nbd_dev
        begin
          syscmd("qemu-nbd --disconnect #{@nbd_dev}")
        rescue SystemCommandFailed
          # pass
        end

        NbdAllocator.free_device(@nbd_dev)
      end

      ok
    end

    protected

    def install_os_template
      mountpoint = Dir.mktmpdir("vpsadmin-vol-#{@name}-")

      if @filesystem == 'btrfs'
        syscmd("mount -o subvolid=5 #{@nbd_dev} #{mountpoint}")
        syscmd("btrfs subvolume create #{File.join(mountpoint, '@')}")
        %w[home root].each { |vol| syscmd("btrfs subvolume create #{File.join(mountpoint, '@', vol)}") }
        syscmd("umount #{mountpoint}")
        syscmd("mount -o subvol=@ #{@nbd_dev} #{mountpoint}")
      else
        syscmd("mount #{@nbd_dev} #{mountpoint}")
      end

      tpl_spec = %w[vendor variant arch distribution version].map { |v| @os_template[v] }

      pid = Process.fork do
        ENV.delete_if do |k, _v|
          k.start_with?('RUBY') || k.start_with?('BUNDLE') || k.start_with?('GEM')
        end

        syscmd("osctl-repo remote get stream #{$CFG.get(:osctl_repo, :url)} #{tpl_spec.join(' ')} tar | tar -xO rootfs/base.tar.gz | tar -xz -C #{mountpoint}/")
      end

      Process.wait(pid)
    ensure
      syscmd("umount #{mountpoint}", valid_rcs: :all)
      Dir.rmdir(mountpoint)
    end

    def vol_path
      File.join(@storage_pool_path, "#{@name}.#{@format}")
    end
  end
end
