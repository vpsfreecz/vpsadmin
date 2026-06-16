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
      string :event_type_pattern, nullable: true
      bool :continue
      integer :hit_count, label: 'Hit count'
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
        use :common, include: %i[user parent_id notification_receiver_id enabled event_type]
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

        %i[user parent_id notification_receiver_id enabled event_type].each do |v|
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
                        enabled event_type event_type_pattern continue]
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

        if owner.event_routes.count >= ::EventRoute::MAX_ROUTES
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
                        enabled event_type event_type_pattern continue]
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
        route.update!(input)
        route
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
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

          route.event_route_matchers.create!(
            field: input[:field],
            operator: input[:operator],
            value: input[:value]
          )
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
          matcher.update!(input)
          matcher
        rescue ActiveRecord::RecordInvalid => e
          error!('update failed', e.record.errors.to_hash)
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
          matcher.destroy!
          ok!
        end
      end
    end
  end
end
