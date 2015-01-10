module VpsAdmind
  class Commands::Pool::Create < Commands::Base
    handle 5250
    use :system, :zfs, :pool

    def exec
      zfs(:create, '-p', @pool_fs)
      zfs(:create, '-p', "#{@pool_fs}/#{pool_work_root}")

      pool_working_dirs.each do |s|
        zfs(:create, '-p', "#{@pool_fs}/#{path_to_pool_working_dir(s)}")
      end
    end

    def rollback
      pool_working_dirs.each do |s|
        zfs(:destroy, nil, "#{@pool_fs}/#{path_to_pool_working_dir(s)}", [1])
      end

      zfs(:destroy, nil, "#{@pool_fs}/#{pool_work_root}", [1])
      zfs(:destroy, nil, @pool_fs, [1])
    end
  end
end
