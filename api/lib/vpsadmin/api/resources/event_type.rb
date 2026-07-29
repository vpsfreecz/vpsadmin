module VpsAdmin::API::Resources
  class EventType < HaveAPI::Resource
    desc 'List event types and matchable fields'

    class Index < HaveAPI::Actions::Default::Index
      desc 'List event types'

      output(:hash_list) do
        string :name
        string :label
        string :category
        string :category_label, label: 'Category label'
        string :severity
        custom :roles
        bool :default_routed
        string :severity_description, nullable: true
        string :template, nullable: true
        custom :fields
        custom :resource, nullable: true
      end

      authorize do |u|
        allow if u
      end

      def count
        VpsAdmin::API::Events::ResourceOperations.refresh_event_types!
        visible_types.count
      end

      def exec
        VpsAdmin::API::Events::ResourceOperations.refresh_event_types!

        visible_types.map do |type|
          {
            name: type.name,
            label: VpsAdmin::API::Events.localized_type_label(type),
            category: type.category,
            category_label:
              VpsAdmin::API::Events::ResourceOperations.category_label(
                type.category
              ),
            severity: type.severity,
            roles: type.roles,
            default_routed: type.default_routed,
            severity_description: VpsAdmin::API::Events.localized_severity_description(type),
            template: type.template,
            resource: type.resource,
            fields: VpsAdmin::API::Events.field_metadata(event_type: type.name).map do |field|
              VpsAdmin::API::Events.localized_field_metadata(
                event_type: type.name,
                field:
              )
            end
          }
        end
      end

      protected

      def visible_types
        types = VpsAdmin::API::Events.types
        return types if current_user.role == :admin

        types.select do |type|
          VpsAdmin::API::Events::ResourceOperations
            .account_visible_event_type?(type)
        end
      end
    end
  end
end
