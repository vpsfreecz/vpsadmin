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
        integer :notification_receiver_action_id, nullable: true
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def query
        q = self.class.model.where(with_restricted)

        %i[user event_type category severity routing_state matched_event_route_id].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end

        delivery_filters = {}
        delivery_filters[:action] = input[:action] if input[:action].present?
        if input[:notification_receiver_id].present?
          delivery_filters[:notification_receiver_id] = input[:notification_receiver_id]
        end
        if input[:notification_receiver_action_id].present?
          delivery_filters[:notification_receiver_action_id] = input[:notification_receiver_action_id]
        end

        if delivery_filters.any?
          q = q.joins(:event_deliveries).where(event_deliveries: delivery_filters).distinct
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query).order(id: :desc))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show event'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        self.class.model.find_by!(with_restricted(id: path_params['event_id']))
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
        integer :event_route_id, nullable: true
        integer :notification_receiver_id, nullable: true
        integer :notification_receiver_action_id, nullable: true
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
        text :payload, nullable: true
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
          restrict events: { user_id: u.id }
          allow
        end

        def query
          self.class.model.joins(:event).where(
            with_restricted(event_id: path_params['event_id'])
          )
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
          restrict events: { user_id: u.id }
          allow
        end

        def exec
          self.class.model.joins(:event).find_by!(
            with_restricted(
              event_id: path_params['event_id'],
              id: path_params['delivery_id']
            )
          )
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
            restrict events: { user_id: u.id }
            allow
          end

          def query
            self.class.model
                .joins(event_delivery: :event)
                .where(
                  with_restricted(
                    event_deliveries: {
                      event_id: path_params['event_id'],
                      id: path_params['delivery_id']
                    }
                  )
                )
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
            restrict events: { user_id: u.id }
            allow
          end

          def exec
            self.class.model
                .joins(event_delivery: :event)
                .find_by!(
                  with_restricted(
                    event_deliveries: {
                      event_id: path_params['event_id'],
                      id: path_params['delivery_id']
                    },
                    id: path_params['attempt_id']
                  )
                )
          end
        end
      end
    end
  end
end
