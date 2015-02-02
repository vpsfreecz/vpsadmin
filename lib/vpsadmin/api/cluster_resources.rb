module VpsAdmin::API
  module ClusterResources
    module InstanceMethods
      def allocate_resource!(env, resource, value, user: nil, confirmed: nil)
        user ||= ::User.current
        confirmed ||= ::ClusterResourceUse.confirmed(:confirm_create)

        user_resource = ::UserClusterResource.find_by(
            user: user,
            environment: env,
            cluster_resource: ::ClusterResource.find_by!(name: resource)
        )

        unless user_resource
          raise Exceptions::UserResourceMissing,
                "user #{user.login} does not have resource #{resource}"
        end

        ::ClusterResourceUse.create!(
            user_cluster_resource: user_resource,
            class_name: self.class.name,
            table_name: self.class.table_name,
            row_id: self.id,
            value: value,
            confirmed: confirmed
        )
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

      def free_resource!(env, resource, user: nil, destroy: false)
        use = ::ClusterResourceUse.joins(:user_cluster_resource).find_by!(
            user_cluster_resources: {
                user: user,
                environment: env,
                cluster_resource: ::ClusterResource.find_by!(name: resource)
            },
            class_name: self.class.name,
            table_name: self.class.table_name,
            row_id: self.id,
        )

        if destroy
          use.destroy!

        else
          use.update!(confirmed: ::ClusterResourceUse.confirmed(:confirm_destroy))
          use
        end
      end
    end

    def self.included(model)
      model.send(:include, InstanceMethods)
    end
  end
end
