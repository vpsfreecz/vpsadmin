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

  class PublicOverview < HaveAPI::Action

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

  class FullOverview < HaveAPI::Action

  end

  include VpsAdmin::API::Maintainable::Action
end
