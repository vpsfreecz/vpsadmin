module NodeCtld
  class Commands::Dataset::Destroy < Commands::Base
    handle 5203

    def exec
      Dataset.new.destroy(@pool_fs, @name, recursive: false, trash: true)
      ok
    end
  end
end
