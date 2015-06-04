if defined?(namespace)
  # Load tasks only if run by rake
  load_rel 'tasks/*.rake'
end

module VpsAdmin::API
  module Tasks
    class Base ; end

    def self.run(klass, task)
      VpsAdmin::API::Tasks.const_get(klass.to_s.classify).new.method(task).call
    end
  end
end

require_rel 'tasks/*.rb'
