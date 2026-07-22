# frozen_string_literal: true

module VpsAdmin::API::Resources
  class EventTimeInterval < HaveAPI::Resource
    desc 'Manage reusable event route time intervals'
    model ::EventTimeInterval

    params(:common) do
      resource User, value_label: :login
      string :name
      string :time_zone, label: 'Time zone'
      custom :specs
    end

    params(:all) do
      id :id
      use :common
      string :display_summary
      bool :matches_now
      integer :route_reference_count
      integer :active_route_reference_count
      integer :mute_route_reference_count
      datetime :created_at
      datetime :updated_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List event route time intervals'

      input do
        resource User, value_label: :login
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        input blacklist: %i[user]
        allow
      end

      def query
        q = self.class.model.where(with_restricted)
        q = q.where(user: input[:user]) if input[:user]
        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query).order(:name, :id))
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show event route time interval'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        self.class.model.find_by!(with_restricted(id: path_params['event_time_interval_id']))
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Create event route time interval'

      input do
        use :common
        patch :name, required: true
        patch :specs, required: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        input blacklist: %i[user]
        allow
      end

      def exec
        owner = current_user.role == :admin && input[:user] ? input[:user] : current_user

        self.class.model.create_for_user!(
          user: owner,
          name: input[:name],
          time_zone: input[:time_zone],
          specs: input[:specs]
        )
      rescue ActiveRecord::RecordInvalid => e
        error!('create failed', e.record.errors.to_hash)
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update event route time interval'

      input do
        use :common, include: %i[name time_zone specs]
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
        interval = self.class.model.find_by!(
          with_restricted(id: path_params['event_time_interval_id'])
        )
        attrs = {}
        %i[name time_zone specs].each do |attr|
          attrs[attr] = input[attr] if input.has_key?(attr)
        end
        interval.update!(attrs)
        interval
      rescue ActiveRecord::RecordInvalid => e
        error!('update failed', e.record.errors.to_hash)
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete event route time interval'

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def exec
        interval = self.class.model.find_by!(
          with_restricted(id: path_params['event_time_interval_id'])
        )
        interval.destroy_if_unassigned!
        ok!
      rescue ActiveRecord::RecordNotDestroyed => e
        error!('interval is assigned to an event route', e.record.errors.to_hash)
      end
    end
  end
end
