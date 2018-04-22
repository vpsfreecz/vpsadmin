module NodeCtld
  class Commands::Node::DeploySshKey < Commands::Base
    handle 7
    needs :system

    def exec
      backup_keys
      write_keys

      ok
    end

    def rollback
      restore_keys

      ok
    end

    def post_save(db)
      db.prepared(
        'UPDATE transactions SET input = ? WHERE id = ?',
        {key_type: @key_type}.to_json, @command.id
      )
    end

    protected
    def backup_keys
      [priv_path, pub_path, authorized_keys].each do |p|
        syscmd("#{$CFG.get(:bin, :cp)} #{p} #{p}.backup") if File.exists?(p)
      end
    end

    def restore_keys
      [priv_path, pub_path, authorized_keys].each do |p|
        syscmd("#{$CFG.get(:bin, :mv)} #{p}.backup #{p}") if File.exists?("#{p}.backup")
      end
    end

    def write_keys
      File.open(priv_path, 'w') do |f|
        f.chmod(0600)
        f.puts(@private_key)
      end

      File.open(pub_path, 'w') do |f|
        f.puts(@public_key)
      end

      File.open(authorized_keys, 'a') do |f|
        f.puts(@public_key)
      end
    end

    def priv_path
      "/root/.ssh/id_#{@key_type}"
    end

    def pub_path
      "#{priv_path}.pub"
    end

    def authorized_keys
      '/root/.ssh/authorized_keys'
    end
  end
end
