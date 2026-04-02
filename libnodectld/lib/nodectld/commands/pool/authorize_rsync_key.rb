module NodeCtld
  class Commands::Pool::AuthorizeRsyncKey < Commands::Base
    handle 5263
    needs :system

    def exec
      add_key
      ok
    end

    def rollback
      remove_key
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

      content = File.read(authorized_keys)
      return if content.lines.any? { |line| line.strip == @pubkey }

      File.open(authorized_keys, 'a') do |f|
        f.write("\n") unless content.empty? || content.end_with?("\n")
        f.write(@pubkey)
        f.write("\n")
      end
    end

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
      File.join(ssh_dir, 'authorized_keys')
    end
  end
end
