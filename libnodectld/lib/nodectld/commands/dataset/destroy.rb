module NodeCtld
  class Commands::Dataset::Destroy < Commands::Base
    handle 5203

    def exec
      Dataset.new.destroy(
        @pool_fs,
        @name,
        recursive: false,
        trash: @pool_role == 'hypervisor'
      )
    end
  end
end
