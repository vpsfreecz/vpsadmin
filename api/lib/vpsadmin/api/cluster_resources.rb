module VpsAdmin::API
  module ClusterResources
    module Private
      def self.define_access_methods(klass, resources)
        resources.each do |r|
          ensure_method(klass, r) do |**kwargs|
            if @cluster_resources && @cluster_resources[r]
              @cluster_resources[r]

            elsif klass.respond_to?(:confirmed) && confirmed.to_sym == :confirm_create
              if kwargs[:default].nil? || kwargs[:default]
                ::DefaultObjectClusterResource.joins(:cluster_resource).find_by!(
                  cluster_resources: {
                    name: r
                  },
                  environment: Private.environment(self),
                  class_name: self.class.name
                ).value
              end

            else
              use = Private.find_resource_use(self, r)

              use ? use.value : 0
            end
          end

          ensure_method(klass, :"#{r}=") do |v|
            @cluster_resources ||= {}
            @cluster_resources[r] = v
          end
        end
      end

      def self.registered_resources(obj)
        obj.class.cluster_resources[:required] + obj.class.cluster_resources[:optional]
      end

      def self.ensure_method(klass, name, &)
        klass.send(:define_method, name, &) unless klass.method_defined?(name)
      end

      def self.find_resource_use(obj, resource)
        ::ClusterResourceUse.joins(
          user_cluster_resource: [:cluster_resource]
        ).find_by(
          user_cluster_resources: {
            environment_id: environment(obj).id
          },
          cluster_resources: {
            name: resource
          },
          class_name: obj.class.name,
          table_name: obj.class.table_name,
          row_id: obj.id
        )
      end

      def self.find_resource_use!(obj, resource)
        ret = find_resource_use(obj, resource)

        raise ActiveRecord::RecordNotFound unless ret

        ret
      end

      def self.environment(obj)
        obj.instance_exec(&obj.class.cluster_resources[:environment])
      end

      def self.user_resource(obj, resource, user, read_lock: false)
        resource_obj = ::ClusterResource.find_by!(name: resource)
        user_resource = ::UserClusterResource.lock(read_lock).find_by(
          user:, environment: environment(obj), cluster_resource: resource_obj
        )
        unless user_resource
          raise Exceptions::UserResourceMissing,
                "user #{user.login} does not have resource #{resource}"
        end

        [resource_obj, user_resource]
      end

      def self.resource_use_scope(obj, resource, user)
        ::ClusterResourceUse.joins(:user_cluster_resource).where(
          user_cluster_resources: {
            user_id: user.id,
            environment_id: environment(obj).id,
            cluster_resource_id: ::ClusterResource.find_by!(name: resource).id
          },
          class_name: obj.class.name,
          table_name: obj.class.table_name,
          row_id: obj.id
        )
      end
    end

    module ClassMethods
      def cluster_resources(required: [], optional: [], environment: nil)
        @cluster_resources ||= {}
        @cluster_resources[:required] ||= []
        @cluster_resources[:optional] ||= []
        @cluster_resources[:environment] ||= environment

        if required.any? || optional.any?
          @cluster_resources[:required].concat(required)
          @cluster_resources[:optional].concat(optional)

          Private.define_access_methods(
            self,
            @cluster_resources[:required] + @cluster_resources[:optional]
          )
        else
          @cluster_resources
        end
      end
    end

    module InstanceMethods
      def allocate_resources(_ = nil, required: nil, optional: nil, user: nil,
                             confirmed: nil, chain: nil, values: {}, admin_override: nil)
        user ||= ::User.current

        required ||= self.class.cluster_resources[:required]
        optional ||= self.class.cluster_resources[:optional]

        resources = {}
        ret = []

        ::ClusterResource.where(name: required + optional).each do |r|
          resources[r.name.to_sym] = r
        end

        required.each do |r|
          ret << allocate_resource!(
            r,
            values[r] || method(r).call,
            user:,
            confirmed:,
            chain:,
            admin_override:
          )
        end

        optional.each do |r|
          use = allocate_resource(
            r,
            values[r] || method(r).call,
            user:,
            confirmed:,
            chain:,
            admin_override:
          )

          ret << use if use.valid?
        end

        ret
      end

      def free_resources(destroy: false, chain: nil, free_objects: true)
        ret = []

        ::ClusterResourceUse.includes(
          user_cluster_resource: [:cluster_resource]
        ).joins(:user_cluster_resource).where(
          class_name: self.class.name,
          table_name: self.class.table_name,
          row_id: id,
          user_cluster_resources: {
            environment_id: Private.environment(self).id
          }
        ).each do |use|
          ret << free_resource!(
            use.user_cluster_resource.cluster_resource.name.to_sym,
            destroy:,
            chain:,
            use:,
            free_object: free_objects
          )
        end

        ret
      end

      def reallocate_resources(resources, user, chain: nil, override: nil, lock_type: nil)
        ret = []
        available = Private.registered_resources(self)

        available.each do |r|
          next unless resources.has_key?(r)

          ret << reallocate_resource!(
            r,
            resources[r],
            user:,
            chain:,
            override:,
            lock_type:
          )
        end

        ret
      end

      def set_cluster_resources(resources)
        available = Private.registered_resources(self)

        available.each do |r|
          method(:"#{r}=").call(resources[r]) if resources.has_key?(r)
        end
      end

      def get_cluster_resources(resources = nil)
        q = ::ClusterResourceUse.includes(
          user_cluster_resource: [:cluster_resource]
        ).joins(user_cluster_resource: [:cluster_resource]).where(
          class_name: self.class.name,
          table_name: self.class.table_name,
          row_id: id,
          user_cluster_resources: {
            environment_id: Private.environment(self).id
          }
        )

        q = q.where(cluster_resources: { name: resources }) if resources
        q
      end

      def allocate_resource(resource, value, user: nil, confirmed: nil,
                            chain: nil, admin_override: nil, read_lock: false)
        user ||= ::User.current
        confirmed ||= ::ClusterResourceUse.confirmed(:confirm_create)
        resource_obj, user_resource = Private.user_resource(self, resource, user, read_lock:)

        chain.lock(user_resource) if chain

        use = ::ClusterResourceUse.new(
          user_cluster_resource: user_resource,
          class_name: self.class.name,
          table_name: self.class.table_name,
          row_id: id,
          value:,
          confirmed:
        )

        use.admin_override = true if admin_override
        use.allocation_read_lock = read_lock
        return use unless use.valid?

        use.save

        if resource_obj.resource_type.to_sym == :object && chain \
           && resource_obj.allocate_chain
          res = chain.use_chain(
            TransactionChains.const_get(resource_obj.allocate_chain),
            args: [resource_obj, self, value],
            method: "allocate_to_#{self.class.name.demodulize.underscore}"
          )

          raise 'not enough' if res != value
        end

        use
      end

      def allocate_resource!(*, **)
        ret = allocate_resource(*, **)

        raise Exceptions::ClusterResourceAllocationError, ret unless ret.persisted?

        ret
      end

      def reallocate_resource!(resource, value, user: nil, save: false, confirmed: nil,
                               chain: nil, override: nil, lock_type: nil)
        user ||= ::User.current
        use = Private.resource_use_scope(self, resource, user).take
        reallocate_resource_use!(resource, use, value, user:, save:, confirmed:, chain:, override:, lock_type:)
      end

      # Apply one relative change using current accounting data. Deferred callers
      # must combine changes to the same usage row before staging confirmations.
      # Returns the usage row in both synchronous and deferred modes.
      def adjust_resource!(resource, delta:, user: nil, save: false, confirmed: nil,
                           chain: nil, override: nil, lock_type: nil)
        raise ArgumentError, 'delta must be an integer' unless delta.is_a?(Integer)
        raise ArgumentError, 'relative changes require save: true or a chain' unless save || chain

        user ||= ::User.current
        self.class.transaction do
          # Lock a separate instance: callers can carry unsaved object changes.
          self.class.find(id).lock!
          _, user_resource = Private.user_resource(self, resource, user)
          change = proc do
            user_resource.lock!
            use = Private.resource_use_scope(self, resource, user).lock.take
            use.user_cluster_resource = user_resource if use
            result = reallocate_resource_use!(
              resource, use, (use&.value || 0) + delta,
              user:, save:, confirmed:, chain:, override:, lock_type:, read_lock: true
            )
            use || result
          end

          if chain
            chain.lock(user_resource)
            change.call
          else
            result = nil
            user_resource.acquire_lock { result = change.call }
            result
          end
        end
      end

      def free_resource!(resource, destroy: false, chain: nil,
                         use: nil, free_object: true)
        resource_obj = (use && use.user_cluster_resource.cluster_resource) \
                        || ::ClusterResource.find_by!(name: resource)

        begin
          use ||= Private.find_resource_use!(self, resource)
        rescue ActiveRecord::RecordNotFound
          # The resource is NOT allocated, no action is needed
          return
        end

        chain.lock(use.user_cluster_resource) if chain

        if resource_obj.resource_type.to_sym == :object && free_object
          chain.use_chain(
            TransactionChains.const_get(resource_obj.free_chain),
            args: [resource_obj, self],
            method: "free_from_#{self.class.name.demodulize.underscore}"
          )
        end

        if destroy
          use.destroy!

        else
          use.admin_override = true
          use.update!(confirmed: ::ClusterResourceUse.confirmed(:confirm_destroy))
          use
        end
      end

      def transfer_resources!(to_user)
        ret = {}
        env = Private.environment(self)
        target_resources = {}

        ::UserClusterResource.includes(:cluster_resource).where(
          environment: env,
          user: to_user
        ).each do |r|
          target_resources[r.cluster_resource.name.to_sym] = r
        end

        ::ClusterResourceUse.includes(
          user_cluster_resource: [:cluster_resource]
        ).joins(:user_cluster_resource).where(
          class_name: self.class.name,
          table_name: self.class.table_name,
          row_id: id,
          user_cluster_resources: {
            environment_id: env.id
          }
        ).each do |use|
          t = target_resources[use.user_cluster_resource.cluster_resource.name.to_sym]

          raise 'target resource does not exist' unless t

          use.user_cluster_resource = t
          use.resource_transfer = true
          raise Exceptions::ClusterResourceAllocationError, use unless use.valid?

          ret[use] = { user_cluster_resource_id: t.id }
        end

        ret
      end

      def transfer_resources_to_env!(user, dst_env, resources = nil)
        ret = {}
        src_env = Private.environment(self)
        target_resources = {}

        ::UserClusterResource.includes(:cluster_resource).where(
          environment: dst_env,
          user:
        ).each do |r|
          target_resources[r.cluster_resource.name.to_sym] = r
        end

        ::ClusterResourceUse.includes(
          user_cluster_resource: [:cluster_resource]
        ).joins(:user_cluster_resource).where(
          class_name: self.class.name,
          table_name: self.class.table_name,
          row_id: id,
          user_cluster_resources: {
            environment_id: src_env.id
          }
        ).each do |use|
          name = use.user_cluster_resource.cluster_resource.name.to_sym
          t = target_resources[name]

          raise 'target resource does not exist' unless t

          use.user_cluster_resource = t
          use.value = resources[name] if resources && resources[name]
          use.resource_transfer = true
          raise Exceptions::ClusterResourceAllocationError, use unless use.valid?

          ret[use] = { user_cluster_resource_id: t.id }
          ret[use][:value] = use.value if resources && resources[name]
        end

        ret
      end

      private

      def reallocate_resource_use!(resource, use, value, user:, save:, confirmed:,
                                   chain:, override:, lock_type:, read_lock: false)
        unless use
          return allocate_resource!(
            resource,
            value,
            user:,
            confirmed:,
            chain:,
            read_lock:
          )
        end

        chain.lock(use.user_cluster_resource) if chain

        use.value = value
        use.admin_override = override
        use.admin_lock_type = lock_type unless lock_type.nil?
        use.allocation_read_lock = read_lock

        if save
          use.save!

        elsif !use.valid?
          raise Exceptions::ClusterResourceAllocationError, use

        else
          use
        end
      end
    end

    def self.included(model)
      model.send(:extend, ClassMethods)
      model.send(:include, InstanceMethods)
    end

    def self.to_params(klass, api, resources: nil)
      resources ||= klass.cluster_resources[:required] + klass.cluster_resources[:optional]

      ::ClusterResource.where(name: resources).each do |r|
        api.integer(
          r.name.to_sym,
          label: r.label,
          desc: "Minimally #{r.min}, maximally #{r.max}, step size is #{r.stepsize}"
        )
      end
    end
  end
end
