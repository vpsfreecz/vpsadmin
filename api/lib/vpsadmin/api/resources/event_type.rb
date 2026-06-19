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
        bool :default_routed
        string :severity_description, nullable: true
        string :email_template, nullable: true
        custom :parameters
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
          fields = VpsAdmin::API::Events.field_labels(event_type: type.name)

          {
            name: type.name,
            label: type.label,
            category: type.category,
            severity: type.severity,
            default_routed: type.default_routed,
            severity_description: type.severity_description,
            email_template: type.email_template,
            parameters: type.parameters,
            fields:
          }
        end
      end
    end
  end
end
