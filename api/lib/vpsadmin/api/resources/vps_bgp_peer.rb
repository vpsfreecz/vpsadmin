class VpsAdmin::API::Resources::VpsBgpPeer < HaveAPI::Resource
  model ::VpsBgpPeer
  desc 'Manage VPS BGP peers'

  params(:all) do
    id :id
    resource VpsAdmin::API::Resources::VPS, value_label: :hostname
    resource VpsAdmin::API::Resources::HostIpAddress, value_label: :addr
    string :protocol, choices: ::VpsBgpPeer.protocols.keys.map(&:to_s)
    integer :node_asn
    integer :vps_asn
    integer :route_limit
    bool :enabled
    datetime :created_at
    datetime :updated_at
  end

  class Index < HaveAPI::Actions::Default::Index
    desc 'List VPS BGP peers'

    input do
      resource VpsAdmin::API::Resources::User, value_label: :login
      use :all, include: %i(
        vps host_ip_address protocol node_asn vps_asn route_limit enabled
      )
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
      q = self.class.model.joins(:vps).where(with_restricted)

      q = q.where(vpses: {user_id: input[:user].id}) if input[:user]

      %i(vps host_ip_address protocol route_limit).each do |v|
        q = q.where(v => input[v]) if input[v]
      end

      %i(node_asn vps_asn).each do |v|
        q = q.joins(:vps_bgp_asn).where(vps_bgp_asns: {v => input[v]}) if input[v]
      end

      q = q.where(enabled: input[:enabled]) if input.has_key?(:enabled)

      q
    end

    def count
      query.count
    end

    def exec
      query.limit(input[:limit]).offset(input[:offset])
    end
  end

  class Show < HaveAPI::Actions::Default::Show
    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict vpses: {user_id: u.id}
      allow
    end

    def prepare
      @peer = self.class.model.joins(:vps).find_by!(with_restricted(
        id: params[:vps_bgp_peer_id],
      ))
    end

    def exec
      @peer
    end
  end

  class Create < HaveAPI::Actions::Default::Create
    desc 'Create a new VPS BGP peer'
    blocking true

    input do
      parameters = %i(vps host_ip_address protocol)

      use :all, include: (parameters + %i(route_limit))

      parameters.each { |v| patch v, required: true }
      patch :route_limit, default: 256, fill: true
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      input blacklist: %i(route_limit)
      allow
    end

    include VpsAdmin::API::Lifetimes::ActionHelpers

    def exec
      # TODO: well, what of non-owned addresses? this needs further thought.

      if current_user.role != :admin \
         && (input[:vps].user_id != current_user.id \
             || input[:host_ip_address].ip_address.user_id != current_user.id)
        error('access denied')
      end

      object_state_check!(input[:vps].user)

      @chain, peer = VpsAdmin::API::Operations::VpsBgp::CreatePeer.run(
        input[:vps],
        input.clone,
      )
      peer

    rescue VpsAdmin::API::Exceptions::OperationError => e
      error(e.message)
    end

    def state_id
      @chain.id
    end
  end

  class Update < HaveAPI::Actions::Default::Update
    desc 'Edit VPS BGP peer'
    blocking true

    input do
      use :all, include: %i(host_ip_address protocol route_limit enabled)
    end

    output do
      use :all
    end

    authorize do |u|
      allow if u.role == :admin
      restrict vpses: {user_id: u.id}
      input blacklist: %i(route_limit)
      allow
    end

    include VpsAdmin::API::Lifetimes::ActionHelpers

    def exec
      peer = self.class.model.find_by!(with_restricted(
        id: params[:vps_bgp_peer_id],
      ))

      object_state_check!(peer.vps.user)

      if input.has_key?(:host_ip_address) && input[:host_ip_address].nil?
        error('cannot unset host_ip_address')
      end

      @chain, peer = VpsAdmin::API::Operations::VpsBgp::UpdatePeer.run(
        peer,
        input.clone,
      )

      peer
    end

    def state_id
      @chain.id
    end
  end

  class Restart < HaveAPI::Action
    desc 'Restart BGP peer'
    route '{%{resource}_id}/restart'
    http_method :post
    blocking true

    authorize do |u|
      allow if u.role == :admin
      restrict vpses: {user_id: u.id}
      allow
    end

    include VpsAdmin::API::Lifetimes::ActionHelpers

    def exec
      peer = self.class.model.find_by!(with_restricted(
        id: params[:vps_bgp_peer_id],
      ))

      object_state_check!(peer.vps.user)

      @chain, peer = VpsAdmin::API::Operations::VpsBgp::RestartPeer.run(peer)
      ok
    end

    def state_id
      @chain.id
    end
  end

  class Delete < HaveAPI::Actions::Default::Delete
    desc 'Delete VPS BGP peer'
    blocking true

    authorize do |u|
      allow if u.role == :admin
      restrict vpses: {user_id: u.id}
      allow
    end

    include VpsAdmin::API::Lifetimes::ActionHelpers

    def exec
      peer = self.class.model.joins(:vps).find_by!(with_restricted(
        id: params[:vps_bgp_peer_id],
      ))

      object_state_check!(peer.vps.user)

      @chain, peer = VpsAdmin::API::Operations::VpsBgp::DestroyPeer.run(peer)
      ok
    end

    def state_id
      @chain.id
    end
  end

  class IpAddress < HaveAPI::Resource
    desc 'Manage announceable IP addresses'
    route '{vps_bgp_peer_id}/ip_addresses'
    model ::VpsBgpIpAddress

    params(:all) do
      id :id
      resource VpsAdmin::API::Resources::IpAddress, value_label: :addr
      string :priority, choices: ::VpsBgpIpAddress.priorities.keys.map(&:to_s)
    end

    class Index < HaveAPI::Actions::Default::Index
      desc 'List IP addresses'

      output(:object_list) do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        allow
      end

      def query
        self.class.model.joins(vps_bgp_peer: :vps).where(with_restricted).where(
          vps_bgp_peers: {id: params[:vps_bgp_peer_id]},
        )
      end

      def count
        query.count
      end

      def exec
        query.limit(input[:limit]).offset(input[:offset])
      end
    end

    class Show < HaveAPI::Actions::Default::Show
      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        allow
      end

      def prepare
        @peer = self.class.model.joins(vps_bgp_peer: :vps).find_by!(with_restricted(
          vps_bgp_peers: {id: params[:vps_bgp_peer_id]},
          id: params[:ip_address_id],
        ))
      end

      def exec
        @peer
      end
    end

    class Create < HaveAPI::Actions::Default::Create
      desc 'Add a new IP address'
      blocking true

      input do
        use :all, include: %i(ip_address priority)
        patch :priority, default: 'normal_priority', fill: true
      end

      output do
        use :all
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        allow
      end

      include VpsAdmin::API::Lifetimes::ActionHelpers

      def exec
        peer = ::VpsBgpPeer.joins(:vps).find_by!(with_restricted(
          id: params[:vps_bgp_peer_id],
        ))

        object_state_check!(peer.vps.user)

        @chain, bgp_ip = VpsAdmin::API::Operations::VpsBgp::AddIp.run(
          peer,
          input.clone,
        )

        bgp_ip

      rescue VpsAdmin::API::Exceptions::OperationError => e
        error(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error('create failed', to_param_names(e.record.errors.to_hash))
      end

      def state_id
        @chain.id
      end
    end

    class Update < HaveAPI::Actions::Default::Update
      desc 'Update IP address'
      blocking true

      input do
        use :all, include: %i(priority)
        patch :priority, required: true
      end

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        allow
      end

      include VpsAdmin::API::Lifetimes::ActionHelpers

      def exec
        ip = self.class.model.joins(vps_bgp_peer: :vps).find_by!(with_restricted(
          vps_bgp_peers: {id: params[:vps_bgp_peer_id]},
          id: params[:ip_address_id],
        ))

        object_state_check!(ip.vps_bgp_peer.vps.user)

        @chain, ret_ip = VpsAdmin::API::Operations::VpsBgp::UpdateIp.run(
          ip,
          input,
        )

        ret_ip
      end

      def state_id
        @chain.id
      end
    end

    class Delete < HaveAPI::Actions::Default::Delete
      desc 'Delete IP address'
      blocking true

      authorize do |u|
        allow if u.role == :admin
        restrict vpses: {user_id: u.id}
        allow
      end

      include VpsAdmin::API::Lifetimes::ActionHelpers

      def exec
        ip = self.class.model.joins(vps_bgp_peer: :vps).find_by!(with_restricted(
          vps_bgp_peers: {id: params[:vps_bgp_peer_id]},
          id: params[:ip_address_id],
        ))

        object_state_check!(ip.vps_bgp_peer.vps.user)

        @chain = VpsAdmin::API::Operations::VpsBgp::DelIp.run(
          ip.vps_bgp_peer,
          ip,
        )

        ok
      end

      def state_id
        @chain.id
      end
    end
  end
end
