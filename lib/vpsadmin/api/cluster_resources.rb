module VpsAdmin::API
  module ClusterResources
    module Private
      def self.define_access_methods(klass, resources)
        resources.each do |r|

          ensure_method(klass, r) do
            if @cluster_resources && @cluster_resources[r]
              @cluster_resources[r]

            elsif klass.respond_to?(:confirmed) && self.confirmed.to_sym == :confirm_create
              ::DefaultObjectClusterResource.joins(:cluster_resource).find_by!(
                  cluster_resources: {
                      name: r
                  },
                  environment: Private.environment(self),
                  class_name: self.class.name
              ).value

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

      def self.ensure_method(klass, name, &block)
        klass.send(:define_method, name, &block) unless klass.method_defined?(name)
      end

      def self.find_resource_use(obj, resource)
        ::ClusterResourceUse.joins(
            user_cluster_resource: [:cluster_resource]
        ).find_by(
            user_cluster_resources: {
                environment_id: environment(obj).id,
            },
            cluster_resources: {
                name: resource
            },
            class_name: obj.class.name,
            table_name: obj.class.table_name,
            row_id: obj.id,
        )
      end

      def self.find_resource_use!(*args)
        ret = find_resource_use(*args)

        raise ActiveRecord::RecordNotFound unless ret

        ret
      end

      def self.environment(obj)
        obj.instance_exec(&obj.class.cluster_resources[:environment])
      end
    end

    module ClassMethods
      def cluster_resources(required: [], optional: [], environment: nil)
        @cluster_resources ||= {}
        @cluster_resources[:required] ||= []
        @cluster_resources[:optional] ||= []
        @cluster_resources[:environment] ||= environment

        if required.size > 0 || optional.size > 0
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
                              confirmed: nil, chain: nil, values: {})
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
              user: user,
              confirmed: confirmed,
              chain: chain
          )
        end

        optional.each do |r|
          use = allocate_resource(
              r,
              values[r] || method(r).call,
              user: user,
              confirmed: confirmed,
              chain: chain
          )

          ret << use if use.valid?
        end

        ret
      end

      def free_resources(destroy: false, chain: nil)
        ret = []

        ::ClusterResourceUse.includes(
            user_cluster_resource: [:cluster_resource]
        ).joins(:user_cluster_resource).where(
            class_name: self.class.name,
            table_name: self.class.table_name,
            row_id: self.id,
            user_cluster_resources: {
                environment_id: Private.environment(self).id
            }
        ).each do |use|
          ret << free_resource!(
              use.user_cluster_resource.cluster_resource.name.to_sym,
              destroy: destroy,
              chain: chain,
              use: use
          )
        end

        ret
      end

      def reallocate_resources(resources, user)
        ret = []
        available = Private.registered_resources(self)

        available.each do |r|
          ret << reallocate_resource!(r, resources[r], user: user) if resources.has_key?(r)
        end

        ret
      end

      def set_cluster_resources(resources)
        available = Private.registered_resources(self)

        available.each do |r|
          method(:"#{r}=").call(resources[r]) if resources.has_key?(r)
        end
      end

      def allocate_resource(resource, value, user: nil, confirmed: nil,
                            chain: nil)
        user ||= ::User.current
        confirmed ||= ::ClusterResourceUse.confirmed(:confirm_create)
        env = Private.environment(self)

        resource_obj = ::ClusterResource.find_by!(name: resource)
        user_resource = ::UserClusterResource.find_by(
            user: user,
            environment: env,
            cluster_resource: resource_obj
        )

        unless user_resource
          raise Exceptions::UserResourceMissing,
                "user #{user.login} does not have resource #{resource}"
        end

        use = ::ClusterResourceUse.create(
            user_cluster_resource: user_resource,
            class_name: self.class.name,
            table_name: self.class.table_name,
            row_id: self.id,
            value: value,
            confirmed: confirmed
        )

        return use unless use.valid?

        if resource_obj.resource_type.to_sym == :object && chain
          res = chain.use_chain(
              TransactionChains.const_get(resource_obj.allocate_chain),
              args: [resource_obj, self, value],
              method: "allocate_to_#{self.class.name.demodulize.underscore}"
          )

          fail 'not enough' if res != value
        end

        use
      end

      def allocate_resource!(*args)
        ret = allocate_resource(*args)

        if ret.persisted?
          ret

        else
          raise ::ActiveRecord::RecordInvalid, ret
        end
      end

      def reallocate_resource!(resource, value, user: nil, save: false, confirmed: nil,
                               chain: nil)
        user ||= ::User.current

        use = ::ClusterResourceUse.joins(:user_cluster_resource).find_by(
            user_cluster_resources: {
                user_id: user.id,
                environment_id: Private.environment(self).id,
                cluster_resource_id: ::ClusterResource.find_by!(name: resource).id
            },
            class_name: self.class.name,
            table_name: self.class.table_name,
            row_id: self.id,
        )

        unless use
          return allocate_resource!(
              resource,
              value,
              user: user,
              confirmed: confirmed,
              chain: chain
          )
        end

        use.value = value

        if save
          use.save!

        elsif !use.valid?
          raise ::ActiveRecord::RecordInvalid, use

        else
          use
        end
      end

      def free_resource!(resource, destroy: false, chain: nil,
                          use: nil)
        resource_obj = (use && use.user_cluster_resource.cluster_resource) \
                        || ::ClusterResource.find_by!(name: resource)

        use ||= Private.find_resource_use!(self, resource)

        if resource_obj.resource_type.to_sym == :object
          chain.use_chain(
              TransactionChains.const_get(resource_obj.free_chain),
              args: [resource_obj, self],
              method: "free_from_#{self.class.name.demodulize.underscore}"
          )
        end

        if destroy
          use.destroy!

        else
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
            row_id: self.id,
            user_cluster_resources: {
                environment_id: env.id
            }
        ).each do |use|

          t = target_resources[use.user_cluster_resource.cluster_resource.name.to_sym]

          fail 'target resource does not exist' unless t

          use.user_cluster_resource = t
          raise ::ActiveRecord::RecordInvalid, use unless use.valid?

          ret[use] = {user_cluster_resource_id: t.id}

        end

        ret
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
