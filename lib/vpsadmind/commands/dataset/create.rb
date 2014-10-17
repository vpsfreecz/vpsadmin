module VpsAdmind
  class Commands::Dataset::Create < Commands::Base
    handle 5201

    def exec
      Dataset.new.create(@pool_fs, @name)
    end
  end
end
