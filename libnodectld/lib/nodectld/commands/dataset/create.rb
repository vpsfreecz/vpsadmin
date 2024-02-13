module NodeCtld
  class Commands::Dataset::Create < Commands::Base
    handle 5201

    include Utils::System
    include Utils::Zfs

    def exec
      opts = if @options
               @options.map { |k, v| "-o #{k}=\"#{translate_property(k, v)}\"" }.join(' ')
             else
               ''
             end

      zfs(:create, "-p #{opts}", "#{@pool_fs}/#{@name}")

      if @create_private
        zfs(:mount, nil, "#{@pool_fs}/#{@name}", valid_rcs: [1])
        mnt = zfs(:get, '-ovalue -H mountpoint', "#{@pool_fs}/#{@name}").output.strip
        syscmd("#{$CFG.get(:bin, :mkdir)} \"#{mnt}/private\"")
      end

      ok
    end

    def rollback
      zfs(:destroy, nil, "#{@pool_fs}/#{@name}", valid_rcs: [1])
    end
  end
end
