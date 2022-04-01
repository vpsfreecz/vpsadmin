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
      Dir.mkdir(root_dir, 0700) unless Dir.exists?(root_dir)
      Dir.mkdir(ssh_dir, 0700) unless Dir.exists?(ssh_dir)

      unless File.exists?(authorized_keys)
        File.open(authorized_keys, 'w') { |f| f.write(@pubkey + "\n") }
        File.chmod(0600, authorized_keys)
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
          return
        end
      end

      # The key is not there yet
      f.write("\n") unless last_line.end_with?("\n")
      f.write(@pubkey)
      f.write("\n")
      f.close
    end

    def remove_key
      return unless File.exists?(authorized_keys)

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
