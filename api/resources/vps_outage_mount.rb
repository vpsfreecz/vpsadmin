module VpsAdmin::API::Resources
  class VpsOutageMount < HaveAPI::Resource
    desc 'Browse VPS mounts affected by outages'
    model ::OutageVpsMount

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::VpsOutage, value_label: :id
      resource VpsAdmin::API::Resources::VPS::Mount, value_label: :mountpoint
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List VPS mounts affected by outage'

      input do
        resource VpsAdmin::API::Resources::Outage, value_label: :begins_at
        resource VpsAdmin::API::Resources::VPS, value_label: :hostname
        resource VpsAdmin::API::Resources::User, value_label: :hostname
        use :all, include: %i(outage_vps)
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        input blacklist: %i(user)
        allow
      end

      def query
        q = ::OutageVpsMount.joins(outage_vps: [:vps]).where(with_restricted)
        q = q.where(outage_vpses: {outage_id: input[:outage].id}) if input[:outage]
        q = q.where(outage_vpses: {vps_id: input[:vps].id}) if input[:vps]
        q = q.where(vpses: {vps_id: input[:user].id}) if input[:user]
        q
      end

      def count
        query.count
      end

      def exec
        with_includes(query)
            .limit(input[:limit])
            .offset(input[:offset])
            .order('outage_vpses.outage_id, outage_vpses.id, outage_vps_mounts.id')
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
        @outage = ::OutageVps.joins(outage_vps: [:vps]).find_by!(with_restricted(
            id: params[:vps_outage_mount_id],
        ))
      end

      def exec
        @outage
      end
    end
  end
end
