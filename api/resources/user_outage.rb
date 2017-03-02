module VpsAdmin::API::Resources
  class UserOutage < HaveAPI::Resource
    desc 'Browse users affected by outages'
    model ::OutageUser

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::Outage, value_label: :begins_at
      resource VpsAdmin::API::Resources::User, value_label: :login
    end
    
    class Index < HaveAPI::Actions::Default::Index
      desc 'List users affected by outage'

      input do
        use :all, include: %i(outage user)
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        allow
      end

      def query
        q = ::OutageUser.joins(:vps).where(with_restricted)
        q = q.where(outage: input[:outage]) if input[:outage]
        q = q.where(vpses: {user_id: input[:user].id}) if input[:user]
        q = q.group('outage_vpses.outage_id, vpses.user_id')
        q
      end

      def count
        query.count.size
      end

      def exec
        with_includes(query)
            .includes(vps: [:user])
            .limit(input[:limit])
            .offset(input[:offset])
            .order('vpses.user_id')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show user affected by an outage'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        allow
      end

      def prepare
        @outage = ::OutageVps.joins(:vps).includes(vps: [:user]).find(params[:user_outage_id])
      end

      def exec
        @outage
      end
    end
  end
end
