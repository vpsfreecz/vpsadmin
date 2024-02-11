module VpsAdmin::API::Resources
  class UserOutage < HaveAPI::Resource
    desc 'Browse users affected by outages'
    model ::OutageUser

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::Outage, value_label: :begins_at
      resource VpsAdmin::API::Resources::User, value_label: :login
      integer :vps_count
      integer :export_count
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List users affected by outage'

      input do
        use :all, include: %i[outage user]
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
        q = ::OutageUser.where(with_restricted)
        q = q.where(outage: input[:outage]) if input[:outage]
        q = q.where(user: input[:user]) if input[:user]
        q
      end

      def count
        query.count.size
      end

      def exec
        with_includes(query)
          .limit(input[:limit])
          .offset(input[:offset])
          .order('outage_users.user_id')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show user affected by an outage'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def prepare
        @outage = with_includes.find(params[:user_outage_id])
      end

      def exec
        @outage
      end
    end
  end
end
