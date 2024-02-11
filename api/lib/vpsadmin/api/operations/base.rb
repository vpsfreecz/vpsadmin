module VpsAdmin::API
  class Operations::Base
    def self.run(*, **)
      op = new
      op.run(*, **)
    end
  end
end
