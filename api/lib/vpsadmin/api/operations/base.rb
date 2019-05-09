module VpsAdmin::API
  class Operations::Base
    def self.run(*args)
      op = new
      op.run(*args)
    end
  end
end
