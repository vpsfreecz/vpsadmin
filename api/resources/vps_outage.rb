module VpsAdmin::API::Resources
  class VpsOutage < HaveAPI::Resource
    desc 'Browse VPSes affected by outages'
    model ::OutageVps

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::Outage, value_label: :begins_at
      resource VpsAdmin::API::Resources::VPS, value_label: :hostname
      resource VpsAdmin::API::Resources::User, value_label: :login
      resource VpsAdmin::API::Resources::Environment
      resource VpsAdmin::API::Resources::Location
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      bool :direct
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List VPSes affected by outage'

      input do
        use :all, include: %i(outage vps user environment location node direct)
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
        q = ::OutageVps.where(with_restricted)

        %i(outage vps user environment location node).each do |v|
          q = q.where(v => input[v]) if input[v]
        end

        q = q.where(direct: input[:direct]) if input.has_key?(:direct)
        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query)
            .limit(input[:limit])
            .offset(input[:offset])
            .order('outage_vpses.id')
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      desc 'Show VPS affected by an outage'

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        allow
      end

      def prepare
        @outage = ::OutageVps.find_by!(with_restricted(
            id: params[:vps_outage_id],
        ))
      end

      def exec
        @outage
      end
    end
  end
end
