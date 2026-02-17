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
      float :duration
      datetime :saved_until
    end

    class Index < HaveAPI::Actions::Default::Index
      input do
        use :all, include: %i[monitor object_name object_id state user]
        string :order, choices: %w[oldest latest longest shortest], default: 'latest',
                       fill: true

        patch :limit, default: 25, fill: true
        float :from_duration, desc: 'Paginate by duration'
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id, state: [
          ::MonitoredEvent.states[:confirmed],
          ::MonitoredEvent.states[:acknowledged],
          ::MonitoredEvent.states[:ignored],
          ::MonitoredEvent.states[:closed]
        ]
        input blacklist: %i[user]
        allow
      end

      def query
        q = ::MonitoredEvent.where(with_restricted).where(
          'access_level <= ?', current_user.level
        )
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
        q = with_includes(query)
        t = ::MonitoredEvent.table_name

        case input[:order]
        when 'oldest'
          with_asc_pagination(q).order("#{t}.created_at")

        when 'latest'
          with_desc_pagination(q).order("#{t}.created_at DESC")

        when 'longest'
          ar_with_pagination(q, parameter: :from_duration) do |q2, from_duration|
            q2.where("TIMESTAMPDIFF(SECOND, #{t}.created_at, #{t}.updated_at) < ?", from_duration)
          end.order(Arel.sql("TIMESTAMPDIFF(SECOND, #{t}.created_at, #{t}.updated_at) DESC"))

        when 'shortest'
          ar_with_pagination(q, parameter: :from_duration) do |q2, from_duration|
            q2.where("TIMESTAMPDIFF(SECOND, #{t}.created_at, #{t}.updated_at) > ?", from_duration)
          end.order(Arel.sql("TIMESTAMPDIFF(SECOND, #{t}.created_at, #{t}.updated_at)"))
        end
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id, state: [
          ::MonitoredEvent.states[:confirmed],
          ::MonitoredEvent.states[:acknowledged],
          ::MonitoredEvent.states[:ignored],
          ::MonitoredEvent.states[:closed]
        ]
        allow
      end

      def prepare
        @event = ::MonitoredEvent.where(with_restricted(
                                          id: params[:monitored_event_id]
                                        )).where(
                                          'access_level <= ?', current_user.level
                                        ).take!
      end

      def exec
        @event
      end
    end

    class Acknowledge < HaveAPI::Action
      http_method :post
      route '{%{resource}_id}/acknowledge'
      aliases %i[ack]

      input do
        datetime :until
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id, state: [
          ::MonitoredEvent.states[:confirmed],
          ::MonitoredEvent.states[:acknowledged],
          ::MonitoredEvent.states[:ignored],
          ::MonitoredEvent.states[:closed]
        ]
        allow
      end

      def exec
        event = ::MonitoredEvent.where(with_restricted(
                                         id: params[:monitored_event_id]
                                       )).where(
                                         'access_level <= ?', current_user.level
                                       ).take!

        unless %w[confirmed acknowledged ignored].include?(event.state)
          error!("events in state '#{event.state}' cannot be acknowledged")
        end

        event.ack!(input[:until])
        ok!
      end
    end

    class Ignore < HaveAPI::Action
      http_method :post
      route '{%{resource}_id}/ignore'

      input do
        datetime :until
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id, state: [
          ::MonitoredEvent.states[:confirmed],
          ::MonitoredEvent.states[:acknowledged],
          ::MonitoredEvent.states[:ignored],
          ::MonitoredEvent.states[:closed]
        ]
        allow
      end

      def exec
        event = ::MonitoredEvent.where(with_restricted(
                                         id: params[:monitored_event_id]
                                       )).where(
                                         'access_level <= ?', current_user.level
                                       ).take!

        unless %w[confirmed acknowledged ignored].include?(event.state)
          error!("events in state '#{event.state}' cannot be ignored")
        end

        event.ignore!(input[:until])
        ok!
      end
    end

    class Log < HaveAPI::Resource
      route '{monitored_event_id}/logs'
      desc 'Browse monitored event logs'
      model ::MonitoredEventLog

      params(:all) do
        id :id
        bool :passed
        custom :value
        datetime :created_at
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List event logs'

        input do
          use :all, include: %i[passed]
          string :order, choices: %w[oldest latest], default: 'oldest', fill: true
          patch :limit, default: 25, fill: true
        end

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict monitored_events: { user_id: u.id }
          allow
        end

        def query
          q = ::MonitoredEventLog.joins(:monitored_event).where(with_restricted(
                                                                  monitored_event_id: params[:monitored_event_id]
                                                                )).where(
                                                                  'monitored_events.access_level <= ?', current_user.level
                                                                )

          q = q.where(passed: input[:passed]) if input.has_key?(:passed)
          q
        end

        def count
          query.count
        end

        def exec
          case input[:order]
          when 'oldest'
            q = with_asc_pagination(query).order('created_at')

          when 'latest'
            q = with_desc_pagination(query).order('created_at DESC')
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
          restrict monitored_events: { user_id: u.id }
          allow
        end

        def prepare
          @event = ::MonitoredEventLog.joins(:monitored_event).where(with_restricted(
                                                                       monitored_event_id: params[:monitored_event_id],
                                                                       id: params[:log_id]
                                                                     )).where(
                                                                       'monitored_events.access_level <= ?', current_user.level
                                                                     ).take!
        end

        def exec
          @event
        end
      end
    end
  end
end
