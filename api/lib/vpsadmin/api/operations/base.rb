module VpsAdmin::API
  class Operations::Base
    def self.run(*args, **kwargs)
      op = new
      op.run(*args, **kwargs)
    end
  end
end
