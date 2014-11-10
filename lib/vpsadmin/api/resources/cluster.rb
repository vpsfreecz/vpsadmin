class VpsAdmin::API::Resources::Cluster < HaveAPI::Resource
  version 1
  desc 'Manage cluster'
  singular true

  class Show < HaveAPI::Actions::Default::Show
    desc 'Cluster information'

    output do
      bool :maintenance_lock
      string :maintenance_lock_reason
    end

    authorize do
      allow
    end

    def exec
      lock = MaintenanceLock.find_by(
          class_name: 'Cluster',
          row_id: nil,
          active: true
      )

      {
          maintenance_lock: lock ? true : false,
          maintenance_lock_reason: lock ? lock.reason : ''
      }
    end
  end

  class PublicStats < HaveAPI::Action
    desc 'Public statistics information'
    auth false

    output do
      integer :user_count, label: 'Number of users'
      integer :vps_count, label: 'Number of VPSes'
      integer :ipv4_left, label: 'Number of free IPv4 addresses'
    end

    authorize do
      allow
    end

    def exec
      {
          user_count: ::User.all.count,
          vps_count: ::Vps.all.count,
          ipv4_left: ::IpAddress.where(vps: nil, version: 4).count
      }
    end
  end

  class FullStats < HaveAPI::Action
    desc 'Full statistics information'

    output(:hash) do
      integer :nodes_online
      integer :node_count
      integer :vps_running
      integer :vps_stopped
      integer :vps_suspended
      integer :vps_deleted
      integer :vps_count
      integer :user_active
      integer :user_suspended
      integer :user_deleted
      integer :user_count
      integer :ipv4_used
      integer :ipv4_count
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      {
          nodes_online: ::Node.joins(:node_status).where('(UNIX_TIMESTAMP() - servers_status.timestamp) <= 150').count,
          node_count: ::Node.all.count,
          vps_running: ::Vps.joins(:vps_status).where(vps_status: {vps_up: true}).count,
          vps_stopped: ::Vps.joins(:vps_status).where(vps_status: {vps_up: false}).count,
          vps_suspended: ::Vps.joins(:user).where(members: {m_state: 'suspended'}).count,
          vps_deleted: ::Vps.unscoped.where.not(vps_deleted: nil).count,
          vps_count: ::Vps.unscoped.all.count,
          user_active: ::User.where(m_state: 'active').count,
          user_suspended: ::User.where(m_state: 'suspended').count,
          user_deleted: ::User.unscoped.where(m_state: 'deleted').count,
          user_count: ::User.unscoped.all.count,
          ipv4_used: ::IpAddress.where.not(vps_id: nil).where(version: 4).count,
          ipv4_count: ::IpAddress.where(version: 4).count
      }
    end
  end

  include VpsAdmin::API::Maintainable::Action
end
