module VpsAdmin::API::Resources
  class EventDelivery < HaveAPI::Resource
    desc 'Browse notification event deliveries'
    model ::EventDelivery

    STATE_GROUPS = {
      'queue' => %w[prepared released sending],
      'log' => %w[sent failed canceled skipped]
    }.freeze

    STATE_GROUP_LABELS = {
      'queue' => 'queue',
      'log' => 'log'
    }.freeze

    params(:all) do
      id :id
      integer :event_id
      integer :event_user_id, nullable: true
      string :event_user_login, nullable: true
      integer :event_vps_id, nullable: true
      string :event_vps_hostname, nullable: true
      string :event_type, nullable: true
      string :event_subject, nullable: true
      string :event_severity, nullable: true
      datetime :event_created_at, nullable: true
      integer :event_route_id, nullable: true
      integer :notification_receiver_id, nullable: true
      string :notification_receiver_label, nullable: true
      integer :notification_receiver_action_id, nullable: true
      string :notification_receiver_action_label, nullable: true
      string :notification_receiver_action_display_target, nullable: true
      string :action,
             choices: { values: ::EventDelivery.action_labels },
             load_validators: false
      string :target_kind,
             choices: { values: ::EventDelivery.target_kind_labels },
             load_validators: false
      text :target_value, nullable: true
      string :target_label, nullable: true
      string :template_name, nullable: true
      string :state,
             choices: { values: ::EventDelivery.state_labels },
             load_validators: false
      integer :mail_log_id, nullable: true
      integer :transaction_id, nullable: true
      integer :attempt_count
      datetime :released_at, nullable: true
      datetime :next_attempt_at, nullable: true
      datetime :last_attempt_at, nullable: true
      string :provider_message_id, nullable: true
      integer :response_status, nullable: true
      text :response_body, nullable: true
      text :error_summary, nullable: true
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List notification event deliveries'

      input do
        resource User, value_label: :login, nullable: true
        string :event_type,
               choices: { values: VpsAdmin::API::Events.type_labels },
               load_validators: false,
               nullable: true
        string :action,
               choices: { values: ::EventDelivery.action_labels },
               load_validators: false,
               nullable: true
        string :state,
               choices: { values: ::EventDelivery.state_labels },
               load_validators: false,
               nullable: true
        string :state_group,
               choices: { values: STATE_GROUP_LABELS },
               load_validators: false,
               nullable: true
        integer :event_route_id, nullable: true
        integer :notification_receiver_id, nullable: true
        integer :notification_receiver_action_id, nullable: true
        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
      end

      def query
        q = self.class.model
                .joins(:event)
                .includes(
                  { event: %i[user vps] },
                  :event_route,
                  :notification_receiver,
                  :notification_receiver_action
                )

        if input[:user]
          user_id = input[:user].respond_to?(:id) ? input[:user].id : input[:user]
          q = q.where(events: { user_id: })
        end
        q = q.where(events: { event_type: input[:event_type] }) if input[:event_type].present?
        q = q.where(action: input[:action]) if input[:action].present?
        q = q.where(event_route_id: input[:event_route_id]) if input[:event_route_id].present?
        if input[:notification_receiver_id].present?
          q = q.where(notification_receiver_id: input[:notification_receiver_id])
        end
        if input[:notification_receiver_action_id].present?
          q = q.where(notification_receiver_action_id: input[:notification_receiver_action_id])
        end

        states = states_filter
        states ? q.where(state: states) : q
      end

      def count
        query.count
      end

      def exec
        with_pagination(query.order(Arel.sql(order_sql)))
      end

      protected

      def states_filter
        states = if input[:state_group].present?
                   STATE_GROUPS.fetch(input[:state_group])
                 end

        if input[:state].present?
          return states ? (states & [input[:state]]) : [input[:state]]
        end

        states
      end

      def order_sql
        case input[:state_group]
        when 'queue'
          queue_order_sql
        when 'log'
          log_order_sql
        else
          'event_deliveries.id DESC'
        end
      end

      def queue_order_sql
        states = ::EventDelivery.states

        <<~SQL.squish
          CASE
            WHEN event_deliveries.state = #{states.fetch('sending')} THEN 0
            WHEN event_deliveries.state = #{states.fetch('released')}
              AND (event_deliveries.next_attempt_at IS NULL OR event_deliveries.next_attempt_at <= CURRENT_TIMESTAMP)
              THEN 1
            WHEN event_deliveries.state = #{states.fetch('released')} THEN 2
            WHEN event_deliveries.state = #{states.fetch('prepared')} THEN 3
            ELSE 4
          END ASC,
          COALESCE(event_deliveries.next_attempt_at, event_deliveries.released_at, event_deliveries.created_at) ASC,
          event_deliveries.id ASC
        SQL
      end

      def log_order_sql
        <<~SQL.squish
          COALESCE(
            event_deliveries.last_attempt_at,
            event_deliveries.released_at,
            event_deliveries.updated_at,
            event_deliveries.created_at
          ) DESC,
          event_deliveries.id DESC
        SQL
      end
    end
  end
end
