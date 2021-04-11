module VpsAdmind
  class Commands::Dataset::SetCanmount < Commands::Base
    handle 5228

    include Utils::System
    include Utils::Zfs

    def exec
      @datasets.each do |name|
        zfs(:set, "canmount=#{@canmount}", "#{@pool_fs}/#{name}")

        if @mount
          zfs(:mount, nil, "#{@pool_fs}/#{name}")
          begin
            zfs(:share, nil, "#{@pool_fs}/#{name}")
          rescue CommandFailed => err
            log "Unable to share #{@pool_fs}/#{name}: #{err.output}"
          end
        end
      end

      ok
    end

    def rollback
      ok
    end
  end
end
