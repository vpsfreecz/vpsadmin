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

  class PublicStatus < HaveAPI::Action

  end

  class FullOverview < HaveAPI::Action

  end

  include VpsAdmin::API::Maintainable::Action
end
