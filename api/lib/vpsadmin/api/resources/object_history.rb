module VpsAdmin::API::Resources
  class ObjectHistory < HaveAPI::Resource
    desc "Browse object's history"
    model ::ObjectHistory

    params(:filters) do
      resource VpsAdmin::API::Resources::User, value_label: :login
      resource VpsAdmin::API::Resources::UserSession, value_label: :api_ip_addr
      string :object, db_name: :tracked_object_type
      integer :object_id, db_name: :tracked_object_id
      string :event_type
    end

    params(:all) do
      id :id
      use :filters
      custom :event_data
      datetime :created_at
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List object history'

      input do
        use :filters
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        input blacklist: %i(user)
        allow
      end

      def query
        q = ::ObjectHistory.where(with_restricted)

        q = q.where(user: input[:user]) if input[:user]
        q = q.where(user_session: input[:user_session]) if input[:user_session]
        q = q.where(tracked_object_type: input[:object]) if input[:object]
        q = q.where(tracked_object_id: input[:object_id]) if input[:object_id]
        q = q.where(event_type: input[:event_type]) if input[:event_type]

        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query)
            .limit(input[:limit])
            .offset(input[:offset])
            .order('created_at, id')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show object history event'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user: u
        allow
      end

      def prepare
        @event = with_includes.where(with_restricted(
            id: params[:history_id]
        )).take!
      end

      def exec
        @event
      end
    end
  end
end
