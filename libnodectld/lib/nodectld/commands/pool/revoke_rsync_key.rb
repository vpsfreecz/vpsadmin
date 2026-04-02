module NodeCtld
  class Commands::Pool::RevokeRsyncKey < Commands::Base
    handle 5264
    needs :system

    def exec
      remove_key
      ok
    end

    def rollback
      ok
    end

    protected

    def remove_key
      return unless File.exist?(authorized_keys)

      tmp = File.join(ssh_dir, '.authorized_keys.new')
      src = File.new(authorized_keys, 'r')
      dst = File.new(tmp, 'w')

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
      File.join(root_dir, '.ssh', 'authorized_keys')
    end
  end
end
