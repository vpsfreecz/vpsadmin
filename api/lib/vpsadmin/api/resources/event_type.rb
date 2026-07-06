module VpsAdmin::API::Resources
  class EventType < HaveAPI::Resource
    desc 'List event types and matchable fields'

    class Index < HaveAPI::Actions::Default::Index
      desc 'List event types'

      output(:hash_list) do
        string :name
        string :label
        string :category
        string :severity
        custom :roles
        bool :default_routed
        string :severity_description, nullable: true
        string :template, nullable: true
        custom :fields
      end

      authorize do |_u|
        allow
      end

      def count
        VpsAdmin::API::Events.types.count
      end

      def exec
        VpsAdmin::API::Events.types.map do |type|
          {
            name: type.name,
            label: VpsAdmin::API::Events.localized_type_label(type),
            category: type.category,
            severity: type.severity,
            roles: type.roles,
            default_routed: type.default_routed,
            severity_description: VpsAdmin::API::Events.localized_severity_description(type),
            template: type.template,
            fields: VpsAdmin::API::Events.field_metadata(event_type: type.name).map do |field|
              VpsAdmin::API::Events.localized_field_metadata(
                event_type: type.name,
                field:
              )
            end
          }
        end
      end
    end
  end
end
