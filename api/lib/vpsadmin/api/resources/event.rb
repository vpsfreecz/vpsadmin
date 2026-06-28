module VpsAdmin::API::Resources
  class Event < HaveAPI::Resource
    desc 'List events'
    model ::Event

    params(:common) do
      resource User, value_label: :login, nullable: true
      string :event_type,
             choices: { values: VpsAdmin::API::Events.type_labels },
             load_validators: false
      string :category
      string :severity,
             choices: { values: ::Event.severity_labels },
             load_validators: false
      string :subject
      text :summary, nullable: true
      text :parameters_json, label: 'Parameters'
      string :source_class, nullable: true
      integer :source_id, nullable: true
      resource VPS, value_label: :hostname, nullable: true
      string :ip_addr, nullable: true
      string :routing_state,
             choices: { values: ::Event.routing_state_labels },
             load_validators: false
      integer :matched_event_route_id, nullable: true
      string :subject_relation,
             choices: { values: ::EventRoutingContext.subject_relation_labels },
             load_validators: false,
             nullable: true
    end

    params(:all) do
      id :id
      use :common
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List events'

      input do
        use :common, include: %i[user event_type category severity routing_state matched_event_route_id]
        string :action,
               choices: { values: ::EventDelivery.action_labels },
               load_validators: false
        integer :notification_receiver_id, nullable: true
        integer :notification_target_id, nullable: true
        integer :notification_receiver_target_id, nullable: true
        string :subject_relation,
               choices: { values: ::EventRoutingContext.subject_relation_labels },
               load_validators: false,
               nullable: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        output blacklist: %i[matched_event_route_id]
        allow
      end

      def query
        q = self.class.model.visible_to(current_user)

        %i[user event_type category severity routing_state].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end
        q = matched_event_route_filter(q)
        q = subject_relation_filter(q)

        delivery_filters = {}
        delivery_filters[:action] = input[:action] if input[:action].present?
        if input[:notification_receiver_id].present?
          delivery_filters[:notification_receiver_id] = input[:notification_receiver_id]
        end
        if input[:notification_target_id].present?
          delivery_filters[:notification_target_id] = input[:notification_target_id]
        end
        if input[:notification_receiver_target_id].present?
          delivery_filters[:notification_receiver_target_id] = input[:notification_receiver_target_id]
        end

        q = delivery_filter(q, delivery_filters) if delivery_filters.any?

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query).order(id: :desc))
      end

      protected

      def matched_event_route_filter(scope)
        return scope unless input.has_key?(:matched_event_route_id)
        return scope.where(matched_event_route_id: input[:matched_event_route_id]) if current_user.role == :admin

        unless ::EventRoute.where(
          id: input[:matched_event_route_id],
          user_id: current_user.id
        ).exists?
          return scope.none
        end

        matching_events = ::EventRoutingContext
                          .where(
                            user_id: current_user.id,
                            matched_event_route_id: input[:matched_event_route_id]
                          )
                          .select(:event_id)

        scope.where(id: matching_events)
      end

      def delivery_filter(scope, filters)
        if current_user.role == :admin
          matching_events = ::EventDelivery
                            .where(filters)
                            .select(:event_id)

          return scope.where(id: matching_events)
        end

        return scope.none unless delivery_filter_visible_to_user?(filters)

        matching_events = ::EventDelivery
                          .joins(:event_routing_context)
                          .where(filters)
                          .where(event_routing_contexts: { user_id: current_user.id })
                          .select(:event_id)

        scope.where(id: matching_events)
      end

      def delivery_filter_visible_to_user?(filters)
        if filters[:notification_receiver_id].present? &&
           !::NotificationReceiver.where(
             id: filters[:notification_receiver_id],
             user_id: current_user.id
           ).exists?
          return false
        end

        if filters[:notification_target_id].present? &&
           !::NotificationTarget.where(
             id: filters[:notification_target_id],
             user_id: current_user.id
           ).exists?
          return false
        end

        receiver_target_exists = ::NotificationReceiverTarget
                                 .joins(:notification_receiver)
                                 .where(
                                   id: filters[:notification_receiver_target_id],
                                   notification_receivers: { user_id: current_user.id }
                                 )
                                 .exists?

        if filters[:notification_receiver_target_id].present? && !receiver_target_exists
          return false
        end

        true
      end

      def subject_relation_filter(scope)
        case input[:subject_relation]
        when 'self'
          scope.where(user_id: current_user.id)
        when 'other_user'
          scope.where.not(user_id: [nil, current_user.id])
        when 'system'
          scope.where(user_id: nil)
        else
          scope
        end
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show event'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        output blacklist: %i[matched_event_route_id]
        allow
      end

      def exec
        self.class.model.visible_to(current_user).find_by!(id: path_params['event_id'])
      end
    end

    class Test < HaveAPI::Action
      TEST_EVENT_LIMIT = 20
      TEST_EVENT_SOURCE_CLASS = 'VpsAdmin::API::Resources::Event::Test'.freeze
      TEST_EVENT_WINDOW = 3600

      desc 'Create a test event and route it'
      route 'test'
      http_method :post

      input do
        resource User, value_label: :login, nullable: true
        string :event_type,
               choices: { values: VpsAdmin::API::Events.type_labels },
               load_validators: false,
               nullable: true
        string :subject, nullable: true
        text :summary, nullable: true
        text :parameters_json, label: 'Parameters', nullable: true
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      def exec
        owner = input[:user] || current_user

        if current_user.role != :admin && owner != current_user
          error!('access denied')
        end

        check_test_event_limit!(owner)

        VpsAdmin::API::Events.emit!(
          input[:event_type] || 'user.test_notification',
          user: owner,
          source_class: TEST_EVENT_SOURCE_CLASS,
          subject: input[:subject] || 'Test notification',
          summary: input[:summary],
          parameters: parse_parameters
        )
      rescue JSON::ParserError
        error!('parameters are not valid JSON')
      rescue ActiveRecord::RecordInvalid => e
        error!('test event failed', e.record.errors.to_hash)
      end

      def parse_parameters
        return { 'note' => 'Sent from notification settings' } if input[:parameters_json].blank?

        if input[:parameters_json].bytesize > ::Event::MAX_PARAMETERS_JSON_SIZE
          error!('parameters are too large')
        end

        ret = JSON.parse(input[:parameters_json])
        error!('parameters must be a JSON object') unless ret.is_a?(Hash)

        ret
      end

      def check_test_event_limit!(owner)
        count = ::Event
                .where(user: owner, source_class: TEST_EVENT_SOURCE_CLASS)
                .where('created_at > ?', Time.now - TEST_EVENT_WINDOW)
                .count
        return if count < TEST_EVENT_LIMIT

        error!('test event limit reached, try again later')
      end
    end

    class Delivery < HaveAPI::Resource
      model ::EventDelivery
      route '{event_id}/deliveries'
      desc 'List event deliveries'

      params(:all) do
        id :id
        integer :event_routing_context_id, nullable: true
        integer :recipient_user_id, nullable: true
        string :recipient_user_login, nullable: true
        integer :event_route_id, nullable: true
        integer :notification_receiver_id, nullable: true
        string :notification_receiver_label, nullable: true
        integer :notification_target_id, nullable: true
        string :notification_target_label, nullable: true
        string :notification_target_display_target, nullable: true
        integer :notification_receiver_target_id, nullable: true
        string :notification_receiver_action_label, label: 'Receiver target label', nullable: true
        string :notification_receiver_action_display_target,
               label: 'Receiver target display target',
               nullable: true
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

      params(:detail) do
        text :payload, nullable: true, db_name: :public_payload
        text :response_headers_json, label: 'Response headers'
        string :mail_to, nullable: true
        string :mail_cc, nullable: true
        string :mail_from, nullable: true
        string :mail_reply_to, nullable: true
        string :mail_return_path, nullable: true
        string :mail_message_id, nullable: true
        string :mail_subject, nullable: true
        text :mail_text_plain, nullable: true
        text :mail_text_html, nullable: true
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List event deliveries'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          output blacklist: %i[template_name]
          allow
        end

        def query
          q = self.class.model
                  .joins(:event)
                  .left_outer_joins(:event_routing_context)
                  .where(event_id: path_params['event_id'])
          return q if current_user.role == :admin

          q.where(events: { user_id: current_user.id })
           .where(event_routing_contexts: { user_id: current_user.id })
        end

        def count
          query.count
        end

        def exec
          with_pagination(query.order(:id))
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show event delivery'

        output do
          use :all
          use :detail
        end

        authorize do |u|
          allow if u.role == :admin
          output blacklist: %i[template_name]
          allow
        end

        def exec
          query.find_by!(id: path_params['delivery_id'])
        end

        def query
          q = self.class.model
                  .joins(:event)
                  .left_outer_joins(:event_routing_context)
                  .where(event_id: path_params['event_id'])
          return q if current_user.role == :admin

          q.where(events: { user_id: current_user.id })
           .where(event_routing_contexts: { user_id: current_user.id })
        end
      end

      class Retry < HaveAPI::Action
        desc 'Retry event delivery'
        route '{delivery_id}/retry'
        http_method :post

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          output blacklist: %i[template_name]
          allow
        end

        def exec
          delivery = query.find_by!(id: path_params['delivery_id'])

          VpsAdmin::API::Notifications::Retry.retry!(delivery)
        rescue VpsAdmin::API::Notifications::Retry::InvalidState => e
          error!(e.message)
        end

        def query
          q = ::EventDelivery
              .joins(:event)
              .left_outer_joins(:event_routing_context)
              .where(event_id: path_params['event_id'])
          return q if current_user.role == :admin

          q.where(events: { user_id: current_user.id })
           .where(event_routing_contexts: { user_id: current_user.id })
        end
      end

      class Attempt < HaveAPI::Resource
        model ::EventDeliveryAttempt
        route '{delivery_id}/attempts'
        desc 'List event delivery attempts'

        params(:all) do
          id :id
          integer :event_delivery_id
          string :action,
                 choices: { values: ::EventDelivery.action_labels },
                 load_validators: false
          string :state,
                 choices: { values: ::EventDeliveryAttempt.state_labels },
                 load_validators: false
          integer :attempt_number
          datetime :started_at, nullable: true
          datetime :finished_at, nullable: true
          string :provider_message_id, nullable: true
          integer :response_status, nullable: true
          text :response_body, nullable: true
          text :response_headers_json, label: 'Response headers'
          text :error_summary, nullable: true
          datetime :created_at
          datetime :updated_at
        end

        class Index < HaveAPI::Actions::Default::Index
          desc 'List event delivery attempts'

          output(:object_list) do
            use :all
          end

          authorize do |u|
            allow if u.role == :admin
            allow
          end

          def query
            q = self.class.model
                    .joins(event_delivery: :event)
                    .left_outer_joins(event_delivery: :event_routing_context)
                    .where(
                      event_deliveries: {
                        event_id: path_params['event_id'],
                        id: path_params['delivery_id']
                      }
                    )
            return q if current_user.role == :admin

            q.where(events: { user_id: current_user.id })
             .where(event_routing_contexts: { user_id: current_user.id })
          end

          def count
            query.count
          end

          def exec
            with_pagination(query.order(:attempt_number))
          end
        end

        class Show < HaveAPI::Actions::Default::Show
          desc 'Show event delivery attempt'

          output do
            use :all
          end

          authorize do |u|
            allow if u.role == :admin
            allow
          end

          def exec
            query.find_by!(id: path_params['attempt_id'])
          end

          def query
            q = self.class.model
                    .joins(event_delivery: :event)
                    .left_outer_joins(event_delivery: :event_routing_context)
                    .where(
                      event_deliveries: {
                        event_id: path_params['event_id'],
                        id: path_params['delivery_id']
                      }
                    )
            return q if current_user.role == :admin

            q.where(events: { user_id: current_user.id })
             .where(event_routing_contexts: { user_id: current_user.id })
          end
        end
      end
    end
  end
end
