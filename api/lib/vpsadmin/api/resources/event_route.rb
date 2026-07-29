require_relative 'event_time_interval'
require_relative 'notification_receiver'

module VpsAdmin::API::Resources
  class EventRoute < HaveAPI::Resource
    desc 'Manage event routes'
    model ::EventRoute

    params(:common) do
      resource User,
               value_label: :login,
               desc: 'User whose events are evaluated by this route'
      string :label,
             desc: 'Optional name used to identify the route',
             nullable: true
      integer :position,
              desc: 'Evaluation order among routes at the same level; lower numbers run first'
      bool :enabled,
           desc: 'Disabled routes and all of their subroutes are ignored'
      string :event_type,
             label: 'Event type',
             desc: 'Match one exact event type; leave empty to match all types or use an event type pattern',
             choices: { values: VpsAdmin::API::Events.type_choice_labels },
             load_validators: false,
             nullable: true
      string :event_type_pattern,
             label: 'Event type pattern',
             desc: 'Shell-style pattern such as monitoring.*; cannot be combined with an exact event type',
             nullable: true
      string :subject_scope,
             label: 'Scope',
             desc: 'Select which event subjects are visible to this route owner',
             choices: { values: ::EventRoute.subject_scope_labels },
             load_validators: false
      bool :grouping_enabled,
           label: 'Group notifications',
           desc: 'Collect matching events and send them together after the configured delay'
      custom :group_by,
             label: 'Group by fields',
             desc: 'Scalar event fields whose values create separate groups; exact routes may use fields from that event type, while patterns and catch-all routes may use common fields only; empty means one group for all matching events'
      integer :group_wait_seconds,
              label: 'Initial wait',
              desc: 'Seconds to wait for more events after the first event opens an idle group',
              nullable: true
      integer :group_interval_seconds,
              label: 'Repeat interval',
              desc: 'Minimum seconds between notifications from a group that remains active',
              nullable: true
      string :grouping_summary,
             desc: 'Human-readable summary of the grouping configuration'
      bool :continue,
           label: 'Continue',
           desc: 'Continue evaluating later sibling routes after this route matches; subroutes are evaluated regardless'
      integer :hit_count, label: 'Hits'
      bool :single_use
      datetime :spent_at, nullable: true
      datetime :expires_at,
               label: 'Expires at',
               desc: 'Optional date and time after which this route stops matching events',
               desc_key: 'vpsadmin.resources.event_route.attributes.expires_at.description',
               nullable: true
      string :matcher_summary
      integer :matcher_count, label: 'Matcher count'
      string :display_label
    end

    params(:associations) do
      resource EventRoute,
               name: :parent_id,
               db_name: :parent_event_route,
               value_label: :display_label,
               label: 'Parent route',
               desc: 'Optional parent; subroutes are evaluated only after their parent matches',
               nullable: true
      resource NotificationReceiver,
               name: :notification_receiver_id,
               db_name: :notification_receiver,
               value_label: :label,
               label: 'Receiver',
               desc: 'Receiver used to deliver matching events; inherit from a parent when empty',
               nullable: true
    end

    params(:all) do
      id :id
      use :common
      # Route lists are a normalized tree. Keep the nullable foreign keys as
      # scalar output fields so clients can assemble that tree without nested
      # self-references; create, update and filter inputs are Resource values.
      integer :parent_id,
              label: 'Parent route',
              desc: 'ID of the parent route in the normalized route tree',
              nullable: true
      integer :notification_receiver_id,
              label: 'Receiver',
              desc: 'ID of the receiver selected by this route',
              nullable: true
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List event routes'

      input do
        use :common, include: %i[user enabled event_type subject_scope]
        use :associations
        bool :include_spent, default: false, fill: true
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
        q = q.where(spent_at: nil) unless input[:include_spent]

        %i[user enabled event_type subject_scope].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
        end
        q = q.where(parent_id: input[:parent_id]&.id) if input.has_key?(:parent_id)
        if input.has_key?(:notification_receiver_id)
          q = q.where(notification_receiver_id: input[:notification_receiver_id]&.id)
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query).order(:parent_id, :position, :id))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show event route'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        self.class.model.find_by!(with_restricted(id: path_params['event_route_id']))
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create event route'

      input do
        use :common, include: %i[user]
        use :associations
        use :common,
            include: %i[label position
                        enabled event_type event_type_pattern subject_scope
                        grouping_enabled group_by group_wait_seconds
                        group_interval_seconds continue]
      end

      output do
        use :all
      end

      authorize do |_u|
        allow
      end

      example 'Create a grouped OOM-report route' do
        request({
                  notification_receiver_id: 15,
                  label: 'OOM report notifications',
                  enabled: true,
                  event_type: 'vps.oom_report',
                  subject_scope: 'self',
                  grouping_enabled: true,
                  group_by: ['vps_id'],
                  group_wait_seconds: 60,
                  group_interval_seconds: 10_800,
                  continue: false
                })
        response({
                   id: 120,
                   notification_receiver_id: 15,
                   label: 'OOM report notifications',
                   event_type: 'vps.oom_report',
                   grouping_enabled: true,
                   group_by: ['vps_id']
                 })
        comment 'New top-level routes are inserted before existing routes.'
      end

      def exec
        owner = input[:user] || current_user

        if current_user.role != :admin && owner != current_user
          error!('access denied')
        end

        if owner.event_routes.active.count >= ::EventRoute::MAX_ROUTES
          error!('route limit reached, refusing to add another one')
        end

        self.class.model.transaction do
          self.class.model.create!(
            user: owner,
            parent_event_route: input[:parent_id],
            notification_receiver: input[:notification_receiver_id],
            label: input[:label],
            position: input.has_key?(:position) ? input[:position] : prepend_position(owner, input[:parent_id]&.id),
            enabled: input.has_key?(:enabled) ? input[:enabled] : true,
            event_type: input[:event_type],
            event_type_pattern: input[:event_type_pattern],
            subject_scope: input[:subject_scope] || 'self',
            grouping_enabled: input.has_key?(:grouping_enabled) ? input[:grouping_enabled] : false,
            group_by: input[:group_by] || [],
            group_wait_seconds: input[:group_wait_seconds],
            group_interval_seconds: input[:group_interval_seconds],
            continue: input.has_key?(:continue) ? input[:continue] : false
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end

      def prepend_position(owner, parent_id)
        self.class.model.prepend_position_for(owner, parent_id)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update event route'

      input do
        use :associations
        use :common,
            include: %i[label position
                        enabled event_type event_type_pattern subject_scope
                        grouping_enabled group_by group_wait_seconds
                        group_interval_seconds continue]
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        route = self.class.model.find_by!(with_restricted(id: path_params['event_route_id']))
        attrs = {}
        %i[
          label position enabled event_type event_type_pattern subject_scope
          grouping_enabled group_by group_wait_seconds group_interval_seconds
          continue
        ].each do |v|
          attrs[v] = input[v] if input.has_key?(v)
        end
        attrs[:parent_event_route] = input[:parent_id] if input.has_key?(:parent_id)
        if input.has_key?(:notification_receiver_id)
          attrs[:notification_receiver] = input[:notification_receiver_id]
        end

        attrs[:template_name] = nil if clears_template_name?(route, attrs)
        route.update!(attrs)
        route
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end

      def clears_template_name?(route, attrs)
        return false if route.template_name.blank?

        %i[parent_event_route event_type event_type_pattern].any? do |v|
          attrs.has_key?(v) && route.public_send(v) != attrs[v]
        end
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete event route'

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        route = self.class.model.find_by!(with_restricted(id: path_params['event_route_id']))
        route.destroy!
        ok!
      end
    end

    class Matcher < HaveAPI::Resource
      model ::EventRouteMatcher
      route '{event_route_id}/matcher'
      desc 'Manage event route matchers'

      params(:common) do
        string :field,
               choices: { values: ::EventRouteMatcher.field_labels },
               load_validators: false
        string :field_type, nullable: true
        string :operator,
               choices: { values: ::EventRouteMatcher.operator_labels },
               load_validators: false
        text :value
        string :summary
      end

      params(:all) do
        id :id
        use :common
        datetime :created_at
        datetime :updated_at
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List event route matchers'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict event_routes: { user_id: u.id }
          allow
        end

        def query
          self.class.model.joins(:event_route).where(
            with_restricted(event_route_id: path_params['event_route_id'])
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
        desc 'Show event route matcher'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict event_routes: { user_id: u.id }
          allow
        end

        def exec
          self.class.model.joins(:event_route).find_by!(
            with_restricted(
              event_route_id: path_params['event_route_id'],
              id: path_params['matcher_id']
            )
          )
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Create event route matcher'

        input do
          use :common, include: %i[field operator value]
          %i[field operator value].each { |v| patch v, required: true }
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict user_id: u.id
          allow
        end

        example 'Match the account event role' do
          path_params 120
          request({
                    field: 'roles',
                    operator: 'contains',
                    value: 'account'
                  })
          response({
                     id: 121,
                     field: 'roles',
                     operator: 'contains',
                     value: 'account'
                   })
          comment 'Add this matcher to an event route with ID 120.'
        end

        def exec
          route = ::EventRoute.find_by!(with_restricted(id: path_params['event_route_id']))

          if route.event_route_matchers.count >= ::EventRoute::MAX_MATCHERS
            error!('matcher limit reached, refusing to add another one')
          end

          route.transaction do
            ret = route.event_route_matchers.create!(
              field: input[:field],
              operator: input[:operator],
              value: input[:value]
            )
            route.update!(template_name: nil) if route.template_name.present?
            ret
          end
        rescue ActiveRecord::RecordInvalid => e
          error!('create failed', e.record.errors.to_hash)
        end
      end

      class Update < HaveAPI::Actions::Default::Update
        desc 'Update event route matcher'

        input do
          use :common, include: %i[field operator value]
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict event_routes: { user_id: u.id }
          allow
        end

        def exec
          matcher = self.class.model.joins(:event_route).find_by!(
            with_restricted(
              event_route_id: path_params['event_route_id'],
              id: path_params['matcher_id']
            )
          )
          attrs = {}
          %i[field operator value].each { |v| attrs[v] = input[v] if input.has_key?(v) }

          matcher.transaction do
            clear_template_name = clears_template_name?(matcher, attrs)
            matcher.update!(attrs)
            matcher.event_route.update!(template_name: nil) if clear_template_name
          end
          matcher
        rescue ActiveRecord::RecordInvalid => e
          error!('update failed', e.record.errors.to_hash)
        end

        def clears_template_name?(matcher, attrs)
          return false if matcher.event_route.template_name.blank?

          attrs.any? do |attr, value|
            matcher.public_send(attr) != value
          end
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Delete event route matcher'

        authorize do |u|
          allow if u.role == :admin
          restrict event_routes: { user_id: u.id }
          allow
        end

        def exec
          matcher = self.class.model.joins(:event_route).find_by!(
            with_restricted(
              event_route_id: path_params['event_route_id'],
              id: path_params['matcher_id']
            )
          )
          matcher.transaction do
            route = matcher.event_route
            matcher.destroy!
            route.update!(template_name: nil) if route.template_name.present?
          end
          ok!
        end
      end
    end

    class TimeInterval < HaveAPI::Resource
      model ::EventRouteTimeInterval
      route '{event_route_id}/time_intervals'
      desc 'Manage time intervals assigned to an event route'

      params(:common) do
        resource VpsAdmin::API::Resources::EventTimeInterval,
                 name: :event_time_interval,
                 value_label: :name
        string :mode,
               choices: { values: ::EventRouteTimeInterval.mode_labels },
               load_validators: false
      end

      params(:all) do
        id :id
        use :common
        datetime :created_at
        datetime :updated_at
      end

      class Index < HaveAPI::Actions::Default::Index
        desc 'List time intervals assigned to an event route'

        output(:object_list) do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict event_routes: { user_id: u.id }
          allow
        end

        def query
          self.class.model.joins(:event_route).where(
            with_restricted(event_route_id: path_params['event_route_id'])
          )
        end

        def count
          query.count
        end

        def exec
          with_pagination(query.includes(:event_time_interval).order(:mode, :id))
        end
      end

      class Show < HaveAPI::Actions::Default::Show
        desc 'Show a time interval assigned to an event route'

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict event_routes: { user_id: u.id }
          allow
        end

        def exec
          self.class.model.joins(:event_route).find_by!(
            with_restricted(
              event_route_id: path_params['event_route_id'],
              id: path_params['time_interval_id']
            )
          )
        end
      end

      class Create < HaveAPI::Actions::Default::Create
        desc 'Assign a time interval to an event route'

        input do
          use :common
          patch :event_time_interval, required: true
          patch :mode, required: true
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict user_id: u.id
          allow
        end

        def exec
          route = ::EventRoute.find_by!(with_restricted(id: path_params['event_route_id']))

          self.class.model.assign!(
            event_route: route,
            event_time_interval: input[:event_time_interval],
            mode: input[:mode]
          )
        rescue ActiveRecord::RecordInvalid => e
          error!('create failed', e.record.errors.to_hash)
        end
      end

      class Update < HaveAPI::Actions::Default::Update
        desc 'Update a time interval assigned to an event route'

        input do
          use :common, include: %i[mode]
        end

        output do
          use :all
        end

        authorize do |u|
          allow if u.role == :admin
          restrict event_routes: { user_id: u.id }
          allow
        end

        def exec
          assignment = self.class.model.joins(:event_route).find_by!(
            with_restricted(
              event_route_id: path_params['event_route_id'],
              id: path_params['time_interval_id']
            )
          )
          assignment.update!(mode: input[:mode]) if input.has_key?(:mode)
          assignment
        rescue ActiveRecord::RecordInvalid => e
          error!('update failed', e.record.errors.to_hash)
        end
      end

      class Delete < HaveAPI::Actions::Default::Delete
        desc 'Unassign a time interval from an event route'

        authorize do |u|
          allow if u.role == :admin
          restrict event_routes: { user_id: u.id }
          allow
        end

        def exec
          assignment = self.class.model.joins(:event_route).find_by!(
            with_restricted(
              event_route_id: path_params['event_route_id'],
              id: path_params['time_interval_id']
            )
          )
          assignment.destroy!
          ok!
        end
      end
    end
  end
end
