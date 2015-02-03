module VpsAdmin::API
  module ClusterResources
    module ClassMethods
      def cluster_resources(required: [], optional: [])
        @cluster_resources ||= {}
        @cluster_resources[:required] ||= []
        @cluster_resources[:optional] ||= []

        if required.size > 0 || optional.size > 0
          @cluster_resources[:required] << required
          @cluster_resources[:optional] << optional

        else
          @cluster_resources
        end
      end
    end

    module InstanceMethods
      def allocate_resources(env, required: nil, optional: nil, user: nil,
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
          ret << allocate_resource!(env, r, values[r], user: user, confirmed: confirmed,
                             chain: chain)
        end

        optional.each do |r|
          use = allocate_resource(env, r, values[r], user: user, confirmed: confirmed,
                                  chain: chain)

          ret << use if use.valid?
        end

        ret
      end

      def free_resources(env, user: nil, destroy: false, chain: nil)
        user ||= ::User.current
        ret = []

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
          ret << free_resource!(
              env,
              use.user_cluster_resource.cluster_resource.name.to_sym,
              user: user,
              destroy: destroy,
              chain: chain,
              use: use
          )
        end

        ret
      end

      def allocate_resource(env, resource, value, user: nil, confirmed: nil,
                            chain: nil)
        user ||= ::User.current
        confirmed ||= ::ClusterResourceUse.confirmed(:confirm_create)

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

        unless value
          value = resource_obj.default_object_cluster_resources.find_by!(
              environment: env,
              class_name: self.class.name
          ).value
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

        if resource_obj.resource_type.to_sym == :object
          unless value

          end

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

      def reallocate_resource!(env, resource, value, user: nil, save: false)
        user ||= ::User.current

        use = ::ClusterResourceUse.joins(:user_cluster_resource).find_by!(
            user_cluster_resources: {
                user_id: user.id,
                environment_id: env.id,
                cluster_resource_id: ::ClusterResource.find_by!(name: resource).id
            },
            class_name: self.class.name,
            table_name: self.class.table_name,
            row_id: self.id,
        )

        use.value = value

        if save
          use.save!

        elsif !use.valid?
          raise ::ActiveRecord::RecordInvalid, use

        else
          use
        end
      end

      def free_resource!(env, resource, user: nil, destroy: false, chain: nil,
                          use: nil)
        user ||= ::User.current
        resource_obj = (use && use.user_cluster_resource.cluster_resource) \
                        || ::ClusterResource.find_by!(name: resource)

        use ||= ::ClusterResourceUse.joins(:user_cluster_resource).find_by!(
            user_cluster_resources: {
                user: user,
                environment: env,
                cluster_resource: resource_obj
            },
            class_name: self.class.name,
            table_name: self.class.table_name,
            row_id: self.id,
        )

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
    end

    def self.included(model)
      model.send(:extend, ClassMethods)
      model.send(:include, InstanceMethods)
    end
  end
end
