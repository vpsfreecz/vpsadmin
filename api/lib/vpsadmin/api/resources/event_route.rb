module VpsAdmin::API::Resources
  class EventRoute < HaveAPI::Resource
    desc 'Manage event routes'
    model ::EventRoute

    params(:common) do
      resource User, value_label: :login
      integer :parent_id, nullable: true
      integer :notification_receiver_id, nullable: true
      string :label, nullable: true
      integer :position
      bool :enabled
      string :event_type,
             choices: { values: VpsAdmin::API::Events.type_labels },
             load_validators: false,
             nullable: true
      string :event_type_pattern, label: 'Event type pattern', nullable: true
      string :subject_scope,
             label: 'Scope',
             choices: { values: ::EventRoute.subject_scope_labels },
             load_validators: false
      bool :continue
      integer :hit_count, label: 'Hits'
      bool :single_use
      datetime :spent_at, nullable: true
      datetime :expires_at, nullable: true
      string :matcher_summary
      string :display_label
    end

    params(:all) do
      id :id
      use :common
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List event routes'

      input do
        use :common, include: %i[user parent_id notification_receiver_id enabled event_type subject_scope]
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

        %i[user parent_id notification_receiver_id enabled event_type subject_scope].each do |v|
          q = q.where(v => input[v]) if input.has_key?(v)
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
        use :common,
            include: %i[user parent_id notification_receiver_id label position
                        enabled event_type event_type_pattern subject_scope continue]
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

        if owner.event_routes.active.count >= ::EventRoute::MAX_ROUTES
          error!('route limit reached, refusing to add another one')
        end

        self.class.model.transaction do
          self.class.model.create!(
            user: owner,
            parent_id: input[:parent_id],
            notification_receiver_id: input[:notification_receiver_id],
            label: input[:label],
            position: input.has_key?(:position) ? input[:position] : next_position(owner, input[:parent_id]),
            enabled: input.has_key?(:enabled) ? input[:enabled] : true,
            event_type: input[:event_type],
            event_type_pattern: input[:event_type_pattern],
            subject_scope: input[:subject_scope] || 'self',
            continue: input.has_key?(:continue) ? input[:continue] : false
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end

      def next_position(owner, parent_id)
        self.class.model.next_position_for(owner, parent_id)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update event route'

      input do
        use :common,
            include: %i[parent_id notification_receiver_id label position
                        enabled event_type event_type_pattern subject_scope continue]
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
        %i[parent_id notification_receiver_id label position enabled event_type event_type_pattern subject_scope continue].each do |v|
          attrs[v] = input[v] if input.has_key?(v)
        end

        attrs[:template_name] = nil if clears_template_name?(route, attrs)
        route.update!(attrs)
        route
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end

      def clears_template_name?(route, attrs)
        return false if route.template_name.blank?

        %i[parent_id event_type event_type_pattern].any? do |v|
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
  end
end
