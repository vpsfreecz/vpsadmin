module VpsAdmin::API::Resources
  class EventDeliveryGroup < HaveAPI::Resource
    desc 'Browse logical notification delivery groups'
    model ::EventDeliveryGroup

    STATE_GROUP_LABELS = {
      'open' => 'open',
      'overdue' => 'overdue',
      'idle' => 'idle'
    }.freeze

    params(:common) do
      id :id
      integer :event_route_id, label: 'Route ID', nullable: true
      string :event_route_label, label: 'Route', nullable: true
      integer :route_owner_id, label: 'Owner ID', nullable: true
      string :route_owner_login, label: 'Owner', nullable: true
      integer :notification_receiver_id, label: 'Receiver ID', nullable: true
      string :notification_receiver_label, label: 'Receiver', nullable: true
      string :state,
             desc: 'Waiting for its deadline, overdue for processing, or idle with no pending events',
             choices: { values: ::EventDeliveryGroup.state_labels },
             load_validators: false
      custom :labels, desc: 'Event field values that identify this group'
      custom :group_by, label: 'Group by fields'
      integer :group_wait_seconds, label: 'Initial wait'
      integer :group_interval_seconds, label: 'Repeat interval'
      integer :pending_event_count, label: 'Pending events'
      integer :stream_count, label: 'Delivery streams'
      datetime :next_flush_at, label: 'Next notification', nullable: true
      datetime :last_sealed_at, label: 'Last notification', nullable: true
    end

    params(:detail) do
      string :group_key, label: 'Group key'
      integer :event_count, label: 'All events'
      custom :actions, desc: 'Delivery actions represented by the group streams'
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List logical notification delivery groups'

      input do
        resource User, name: :route_owner, value_label: :login, nullable: true
        integer :event_route_id, nullable: true
        integer :notification_receiver_id, nullable: true
        string :state_group,
               choices: { values: STATE_GROUP_LABELS },
               load_validators: false,
               nullable: true
        patch :limit, default: 25, fill: true
      end

      output(:object_list) do
        use :common
      end

      authorize do |u|
        allow if u.role == :admin
        restrict route_owner_id: u.id
        input blacklist: %i[route_owner]
        allow
      end

      def query
        filtered_query
          .includes(:event_route, :notification_receiver, :route_owner)
          .select(
            'event_delivery_groups.*',
            pending_event_count_sql,
            stream_count_sql
          )
      end

      def count
        filtered_query.count
      end

      def exec
        with_pagination(query.order(Arel.sql(order_sql)))
      end

      protected

      def filtered_query
        q = self.class.model.where(with_restricted)

        if input[:route_owner]
          q = q.where(route_owner_id: input[:route_owner].id)
        end
        q = q.where(event_route_id: input[:event_route_id]) if input[:event_route_id].present?
        if input[:notification_receiver_id].present?
          q = q.where(notification_receiver_id: input[:notification_receiver_id])
        end

        case input[:state_group]
        when 'open'
          q.where.not(next_flush_at: nil)
        when 'overdue'
          q.where.not(next_flush_at: nil).where(next_flush_at: ..Time.now)
        when 'idle'
          q.where(next_flush_at: nil)
        else
          q
        end
      end

      def pending_event_count_sql
        grouping_state = ::EventDelivery.states.fetch('grouping')

        <<~SQL.squish
          (
            SELECT COUNT(DISTINCT pending_deliveries.event_id)
            FROM event_deliveries AS pending_deliveries
            WHERE pending_deliveries.event_delivery_group_id = event_delivery_groups.id
              AND pending_deliveries.state = #{grouping_state}
          ) AS pending_event_count
        SQL
      end

      def stream_count_sql
        <<~SQL.squish
          (
            SELECT COUNT(DISTINCT stream_deliveries.group_stream_key)
            FROM event_deliveries AS stream_deliveries
            WHERE stream_deliveries.event_delivery_group_id = event_delivery_groups.id
              AND stream_deliveries.group_stream_key IS NOT NULL
          ) AS stream_count
        SQL
      end

      def order_sql
        <<~SQL.squish
          CASE
            WHEN event_delivery_groups.next_flush_at IS NOT NULL
              AND event_delivery_groups.next_flush_at <= CURRENT_TIMESTAMP THEN 0
            WHEN event_delivery_groups.next_flush_at IS NOT NULL THEN 1
            ELSE 2
          END ASC,
          event_delivery_groups.next_flush_at ASC,
          event_delivery_groups.updated_at DESC,
          event_delivery_groups.id DESC
        SQL
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show logical notification delivery group'

      output do
        use :common
        use :detail
      end

      authorize do |u|
        allow if u.role == :admin
        restrict route_owner_id: u.id
        allow
      end

      def exec
        self.class.model
            .includes(:event_route, :notification_receiver, :route_owner)
            .find_by!(with_restricted(id: path_params['event_delivery_group_id']))
      end
    end
  end
end
