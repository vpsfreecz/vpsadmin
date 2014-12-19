module VpsAdmind
  class Commands::Dataset::Create < Commands::Base
    handle 5201

    include Utils::System
    include Utils::Zfs

    def exec
      if @options
        opts = @options.map { |k, v| "-o #{k}=\"#{v}\""  }.join(' ')
      else
        opts = ''
      end

      zfs(:create, "-p #{opts}", "#{@pool_fs}/#{@name}")
    end

    def rollback
      zfs(:destroy, nil, "#{@pool_fs}/#{@name}")
    end
  end
end
