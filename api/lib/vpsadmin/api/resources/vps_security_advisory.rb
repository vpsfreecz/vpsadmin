module VpsAdmin::API::Resources
  class VpsSecurityAdvisory < HaveAPI::Resource
    desc 'Browse VPSes affected by security advisories'
    model ::SecurityAdvisoryVps

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::SecurityAdvisory, value_label: :id
      resource VpsAdmin::API::Resources::VPS, value_label: :hostname
      resource VpsAdmin::API::Resources::User, value_label: :login
      resource VpsAdmin::API::Resources::Environment
      resource VpsAdmin::API::Resources::Location
      resource VpsAdmin::API::Resources::Node, value_label: :domain_name
      string :node_state, choices: ::SecurityAdvisoryNodeStatus.states.keys.map(&:to_s)
      datetime :vulnerable_until, nullable: true
      datetime :mitigated_since, nullable: true
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List VPSes affected by security advisory'

      input do
        use :all, include: %i[security_advisory vps user environment location node]
      end

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict user_id: u.id
        output blacklist: %i[user]
        input blacklist: %i[user]
        allow
      end

      def query
        q = ::SecurityAdvisoryVps
            .joins(:security_advisory)
            .merge(::SecurityAdvisory.visible_to(current_user))
            .where(with_restricted)

        %i[security_advisory vps user environment location node].each do |v|
          q = q.where(v => input[v]) if input[v]
        end

        q
      end

      def count
        query.count
      end

      def exec
        with_pagination(with_includes(query)).order('security_advisory_vpses.id')
      end
    end
  end
end
