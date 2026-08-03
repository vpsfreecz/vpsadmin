module VpsAdmin::API
  class Operations::Base
    extend VpsAdmin::API::Events::ActionPolicies::PolicyDeclaration

    def self.run(*, **)
      op = new
      op.run(*, **)
    end
  end
end
