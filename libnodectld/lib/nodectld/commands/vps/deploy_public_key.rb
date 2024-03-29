module NodeCtld
  class Commands::Vps::DeployPublicKey < Commands::Base
    handle 2017
    needs :system, :osctl, :vps

    def exec
      fork_chroot_wait { add_key }
      ok
    end

    def rollback
      fork_chroot_wait { remove_key }
      ok
    end

    protected

    def add_key
      FileUtils.mkdir_p(root_dir, mode: 0o700)
      FileUtils.mkdir_p(ssh_dir, mode: 0o700)

      unless File.exist?(authorized_keys)
        File.write(authorized_keys, "#{@pubkey}\n")
        File.chmod(0o600, authorized_keys)
        return
      end

      # Walk through the file, write the key if it is not there yet
      # For some reason, when File.open is given a block, it does not raise
      # exceptions like "Errno::EDQUOT: Disk quota exceeded", so don't use it.
      f = File.open(authorized_keys, 'r+')
      last_line = ''

      f.each_line do |line|
        last_line = line

        if line.strip == @pubkey
          f.close
          return # rubocop:disable Lint/NonLocalExitFromIterator
        end
      end

      # The key is not there yet
      f.write("\n") unless last_line.end_with?("\n")
      f.write(@pubkey)
      f.write("\n")
      f.close
    end

    def remove_key
      return unless File.exist?(authorized_keys)

      tmp = File.join(ssh_dir, '.authorized_keys.new')

      src = File.open(authorized_keys, 'r')
      dst = File.open(tmp, 'w')

      src.each_line do |line|
        next if line.strip == @pubkey

        dst.write(line)
      end

      src.close
      dst.close

      File.rename(tmp, authorized_keys)
    end

    def root_dir
      '/root'
    end

    def ssh_dir
      File.join(root_dir, '.ssh')
    end

    def authorized_keys
      File.join(ssh_dir, 'authorized_keys')
    end
  end
end
