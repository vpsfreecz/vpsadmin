module VpsAdmind
  class Commands::Dataset::Create < Commands::Base
    handle 5201

    include Utils::System
    include Utils::Zfs

    def exec
      if @options
        opts = @options.map { |k, v| "-o #{k}=\"#{translate_property(k, v)}\""  }.join(' ')
      else
        opts = ''
      end

      zfs(:create, "-p #{opts}", "#{@pool_fs}/#{@name}")

      if @create_private
        mnt = zfs(:get, '-ovalue -H mountpoint', "#{@pool_fs}/#{@name}")[:output].strip
        syscmd("#{$CFG.get(:bin, :mkdir)} \"#{mnt}/private\"")
      end

      ok
    end

    def rollback
      zfs(:destroy, nil, "#{@pool_fs}/#{@name}")
    end
  end
end
