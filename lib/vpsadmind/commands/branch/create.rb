module VpsAdmind
  class Commands::Branch::Create < Commands::Base
    handle 5206

    include Utils::System
    include Utils::Zfs

    def exec
      new_branch = "#{@pool_fs}/#{@dataset_name}/#{@tree}/#{@new_branch_name}"

      if @from_branch_name
        from = "#{@pool_fs}/#{@dataset_name}/#{@tree}/#{@from_branch_name}@#{@from_snapshot}"

        zfs(:clone, nil, "#{from} #{new_branch}")
        zfs(:promote, nil, new_branch)

      else
        zfs(:create, nil, "#{new_branch}")
      end
    end
  end
end
