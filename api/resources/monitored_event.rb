module VpsAdmin::API::Resources
  class MonitoredEvent < HaveAPI::Resource
    desc 'Browser monitored events'
    model ::MonitoredEvent

    params(:all) do
      id :id
      string :monitor, db_name: :monitor_name
      string :label
      string :issue
      string :object_name, db_name: :class_name
      integer :object_id, db_name: :row_id
      string :state, choices: ::MonitoredEvent.states.keys.map(&:to_s)
      resource VpsAdmin::API::Resources::User, value_label: :login
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        use :all, include: %i(monitor object_name object_id state user)
        string :order, choices: %w(oldest latest longest shortest), default: 'latest',
            fill: true

        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        input blacklist: %i(user)
        allow
      end

      def query
        q = ::MonitoredEvent.where(with_restricted)
        q = q.where(monitor_name: input[:monitor]) if input[:monitor]
        q = q.where(class_name: input[:object_name]) if input[:object_name]
        q = q.where(row_id: input[:object_id]) if input[:object_id]
        q = q.where(state: ::MonitoredEvent.states[input[:state]]) if input[:state]
        q = q.where(user: input[:user]) if input[:user]
        q
      end

      def count
        query.count
      end

      def exec
        q = with_includes(query).limit(input[:limit]).offset(input[:offset])
        t = ::MonitoredEvent.table_name

        case input[:order]
        when 'oldest'
          q = q.order("#{t}.created_at")

        when 'latest'
          q = q.order("#{t}.created_at DESC")

        when 'longest'
          q = q.order("TIMESTAMPDIFF(SECOND, #{t}.created_at, #{t}.updated_at) DESC")

        when 'shortest'
          q = q.order("TIMESTAMPDIFF(SECOND, #{t}.created_at, #{t}.updated_at)")
        end

        q
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
