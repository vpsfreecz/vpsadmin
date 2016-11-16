module VpsAdmind
  class Commands::Vps::DeployPublicKey < Commands::Base
    handle 2017
    needs :system, :vps

    def exec
      unless Dir.exists?(root_dir)
        raise CommandFailed.new('', 1, "root homedir '#{root_dir}' not found")
      end

      unless Dir.exists?(ssh_dir)
        Dir.mkdir(ssh_dir)
        File.chmod(0700, ssh_dir)
      end

      unless File.exists?(authorized_keys)
        File.open(authorized_keys, 'w') { |f| f.write(@pubkey + "\n") }
        File.chmod(0600, authorized_keys)
        return ok
      end
      
      # Walk through the file, write the key if it is not there yet
      File.open(authorized_keys, 'r+') do |f|
        last_line = ''

        f.each_line do |line|
          last_line = line

          if line.strip == @pubkey
            f.close
            return ok
          end
        end

        # The key is not there yet
        f.write("\n") unless last_line.end_with?("\n")
        f.write(@pubkey)
        f.write("\n")
      end

      ok
    end

    def rollback
      return ok unless File.exists?(authorized_keys)
      
      tmp = File.join(ssh_dir, '.authorized_keys.new')

      src = File.open(authorized_keys, 'r')
      dst = File.open(tmp, 'w')

      src.each_line do |line|
        next if line.strip == @pubkey
        dst.write(line)
      end

      src.close
      dst.close

      syscmd("#{$CFG.get(:bin, :mv)} \"#{tmp}\" \"#{authorized_keys}\"")
      ok
    end

    protected
    def root_dir
      File.join(ve_private, 'root')
    end

    def ssh_dir
      File.join(root_dir, '.ssh')
    end

    def authorized_keys
      File.join(ssh_dir, 'authorized_keys')
    end
  end
end
