module NodeCtld
  class Commands::Dataset::Destroy < Commands::Base
    handle 5203

    def exec
      Dataset.new.destroy(@pool_fs, @name, false)
    end
  end
end
