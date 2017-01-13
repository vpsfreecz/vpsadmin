if defined?(namespace)
  # Load tasks only if run by rake
  load_rel 'tasks/*.rake'
end

module VpsAdmin::API
  module Tasks
    class Base
      def required_env(vars)
        (vars.is_a?(Array) ? vars : [vars]).each do |env|
          next if ENV[env] && ENV[env].length > 0

          fail "Missing required environment variable #{env}"
        end
      end
    end

    def self.run(klass, task)
      VpsAdmin::API::Tasks.const_get(klass.to_s.classify).new.method(task).call
    end
  end
end

require_rel 'tasks/*.rb'
