class VpsAdmin::API::Resources::Cluster < HaveAPI::Resource
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
      integer :ipv4_left, label: 'Number of free public IPv4 addresses'
    end

    authorize do
      allow
    end

    example do
      response({
        user_count: 1100,
        vps_count: 1560,
        ipv4_left: 256,
      })
    end

    def exec
      {
        user_count: ::User.unscoped.where(
          object_state: [
              ::User.object_states[:active],
              ::User.object_states[:suspended],
          ]
        ).count,
        vps_count: ::Vps.unscoped.where(
          object_state: [
              ::Vps.object_states[:active],
              ::Vps.object_states[:suspended],
          ]
        ).count,
        ipv4_left: ::IpAddress.joins(:network).where(
          user: nil,
          network_interface: nil,
          networks: {
            ip_version: 4,
            role: ::Network.roles[:public_access],
          },
        ).count,
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
      t = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')

      {
        nodes_online: ::Node.joins(:node_current_status).where(
          "TIMEDIFF(?, node_current_statuses.created_at) <= CAST('00:02:30' AS TIME)
            OR TIMEDIFF(?, node_current_statuses.updated_at) <= CAST('00:02:30' AS TIME)",
          t, t
        ).count,
        node_count: ::Node.all.count,
        vps_running: ::Vps.joins(:vps_current_status).where(
          vps_current_statuses: {is_running: true}
        ).count,
        vps_stopped: ::Vps.joins(:vps_current_status).where(
          vps_current_statuses: {is_running: false}
        ).count,
        vps_suspended: ::Vps.joins(:user).where(
          'users.object_state = ? OR vpses.object_state = ?',
          ::User.object_states['suspended'], ::Vps.object_states['suspended']
        ).count,
        vps_deleted: ::Vps.unscoped.where(
          object_state: ::Vps.object_states['soft_delete']
        ).count,
        vps_count: ::Vps.unscoped.all.count,
        user_active: ::User.where(
          object_state: ::User.object_states['active']
        ).count,
        user_suspended: ::User.where(
          object_state: ::User.object_states['suspended']
        ).count,
        user_deleted: ::User.unscoped.where(
          object_state: ::User.object_states['soft_delete']
        ).count,
        user_count: ::User.unscoped.all.count,
        ipv4_used: ::IpAddress.joins(:network).where.not(network_interface: nil).where(
          networks: {
            ip_version: 4,
            role: ::Network.roles[:public_access],
          }
        ).count,
        ipv4_count: ::IpAddress.joins(:network).where(
          networks: {
            ip_version: 4,
            role: ::Network.roles[:public_access],
          }
        ).count,
      }
    end
  end

  class Search < HaveAPI::Action
    http_method :post
    desc 'Search users and VPSes by IDs, names and owned objects'

    input(:hash) do
      string :value, label: 'Value', desc: 'Value to be searched for',
          required: true
    end

    output(:hash_list) do
      string :resource, label: 'Resource', desc: 'Resource name of the located object'
      integer :id, label: 'ID', desc: 'Identifier of the located object'
      string :attribute, label: 'Attribute',
          desc: 'Name of the attribute containing the searched value'
      string :value, label: 'Value', desc: 'Located value'
    end

    authorize do |u|
      allow if u.role == :admin
    end

    def exec
      ::Cluster.search(input[:value].strip)
    end
  end

  include VpsAdmin::API::Maintainable::Action
end
