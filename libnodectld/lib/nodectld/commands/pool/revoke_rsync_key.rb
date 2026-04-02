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
      return unless Dir.exist?(ssh_dir)

      with_authorized_keys_lock do
        if File.exist?(authorized_keys)
          tmp = File.join(ssh_dir, '.authorized_keys.new')

          File.open(authorized_keys, 'r') do |src|
            File.open(tmp, 'w') do |dst|
              src.each_line do |line|
                next if line.strip == authorized_key

                dst.write(line)
              end
            end
          end

          File.chmod(0o600, tmp)
          File.rename(tmp, authorized_keys)
        end
      end
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

    def authorized_key
      "#{@pubkey.strip} #{marker}"
    end

    def marker
      "vpsadmin-rsync-chain=#{@command.chain_id}"
    end

    def lock_path
      File.join(ssh_dir, '.authorized_keys.vpsadmin-rsync.lock')
    end

    def with_authorized_keys_lock
      File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      ensure
        lock.flock(File::LOCK_UN)
      end
    end
  end
end
