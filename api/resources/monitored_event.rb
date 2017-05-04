module VpsAdmin::API::Resources
  class MonitoredEvent < HaveAPI::Resource
    desc 'Browser monitored events'
    model ::MonitoredEvent

    params(:all) do
      id :id
      string :monitor, db_name: :monitor_name
      string :label
      string :issue
      string :class_name
      integer :object_id, db_name: :row_id
      string :state, choices: ::MonitoredEvent.states.keys.map(&:to_s)
      resource VpsAdmin::API::Resources::User, value_label: :login
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def query
        ::MonitoredEvent.where(with_restricted)
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def prepare
        @event = ::MonitoredEvent.find_by!(with_restricted(
            id: params[:monitored_event_id],
        ))
      end

      def exec
        @event
      end
    end

    class Acknowledge < HaveAPI::Action
      http_method :post
      route ':%{resource}_id/acknowledge'
      aliases %i(ack)

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        ::MonitoredEvent.find_by!(with_restricted(
            id: params[:monitored_event_id],
        )).ack!
        ok
      end
    end

    class Ignore < HaveAPI::Action
      http_method :post
      route ':%{resource}_id/ignore'

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        ::MonitoredEvent.find_by!(with_restricted(
            id: params[:monitored_event_id],
        )).ignore!
        ok
      end
    end
  end
end
