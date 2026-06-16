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
            parameters: type.parameters,
            fields:
          }
        end
      end
    end
  end
end
