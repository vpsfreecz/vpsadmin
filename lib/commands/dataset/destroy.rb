module VpsAdmind
  class Commands::Dataset::Destroy < Commands::Base
    handle 5203

    def exec
      Dataset.new.destroy(@pool_fs, @name, true)
    end
  end
end
