module VpsAdmind
  class Commands::Dataset::SetCanmount < Commands::Base
    handle 5228

    include Utils::System
    include Utils::Zfs

    def exec
      @datasets.each do |name|
        zfs(:set, "canmount=#{@canmount}", "#{@pool_fs}/#{name}")
        zfs(:mount, nil, "#{@pool_fs}/#{name}") if @mount
      end

      ok
    end

    def rollback
      ok
    end
  end
end
