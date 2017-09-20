module VpsAdmind
  class Commands::Branch::Create < Commands::Base
    handle 5206

    include Utils::System
    include Utils::Zfs

    def exec
      if @from_branch_name
        zfs(:clone, nil, "#{from_branch}@#{@from_snapshot} #{new_branch}")
        zfs(:promote, nil, new_branch)

      else
        zfs(:create, nil, "#{new_branch}")
      end
    end

    def rollback
      if @from_branch_name
        zfs(:promote, nil, from_branch)
      end

      zfs(:destroy, nil, new_branch)
    end

    protected
    def from_branch
      "#{@pool_fs}/#{@dataset_name}/#{@tree}/#{@from_branch_name}"
    end

    def new_branch
      "#{@pool_fs}/#{@dataset_name}/#{@tree}/#{@new_branch_name}"
    end
  end
end
