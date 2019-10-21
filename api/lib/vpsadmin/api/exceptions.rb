require 'haveapi'

module VpsAdmin::API::Exceptions
  class AuthenticationError < HaveAPI::AuthenticationError

  end

  class AccessDenied < ::StandardError

  end

  class IpAddressInUse < ::StandardError

  end

  class IpAddressNotAssigned < ::StandardError

  end

  class IpAddressInvalidLocation < ::StandardError

  end

  class IpAddressNotOwned < ::StandardError

  end

  class IpAddressInvalid < ::StandardError

  end

  class DatasetAlreadyExists < ::StandardError
    attr_reader :dataset, :path

    def initialize(ds, path)
      @dataset = ds
      @path = path
      super("dataset '#{path}' already exists")
    end
  end

  class DatasetDoesNotExist < ::StandardError
    attr_reader :path

    def initialize(path)
      @path = path
      super("dataset '#{path}' does not exist")
    end
  end

  class DatasetLabelDoesNotExist < ::StandardError
    attr_reader :label

    def initialize(label)
      @label = label
      super("dataset label '#{label}' does not exist")
    end
  end

  class SnapshotAlreadyMounted < ::StandardError
    attr_reader :snapshot

    def initialize(snapshot)
      @snapshot = snapshot
      super("snapshot '#{snapshot.dataset_in_pool.dataset.full_name}@#{snapshot.snapshot.name}' is already mounted to VPS #{snapshot.mount.vps_id} at #{snapshot.mount.dst}")
    end
  end

  class SnapshotInUse < ::StandardError
    attr_reader :snapshot

    def initialize(snapshot)
      @snapshot = snapshot
      super("snapshot '#{snapshot.dataset_in_pool.dataset.full_name}@#{snapshot.snapshot.name}' is in use")
    end
  end

  class DatasetPlanNotInEnvironment < ::StandardError
    attr_reader :dataset_plan, :environment

    def initialize(plan, env)
      @dataset_plan = plan
      @environment = env

      super("Dataset plan #{plan} is not available in environment #{env.label}")
    end
  end

  class PropertyInvalid < ::StandardError

  end

  class InvalidRefquotaDataset < ::StandardError

  end

  class DatasetNestingForbidden < ::StandardError

  end

  class RefquotaCheckFailed < ::StandardError

  end

  class UserResourceMissing < ::StandardError

  end

  class UserResourceAllocationError < ::StandardError

  end

  class CannotLeaveState < ::StandardError

  end

  class TooManyParameters < ::StandardError

  end

  class MailTemplateDoesNotExist < ::StandardError
    def initialize(name)
      super("Mail template '#{name}' does not exist")
    end
  end

  class MailTemplateDisabled < ::StandardError
    def initialize(name)
      super("Mail template '#{name}' is disabled")
    end
  end

  class ClusterResourceAllocationError < ::StandardError
    attr_reader :resource_use

    def initialize(record)
      @resource_use = record
      super("#{record.errors.to_hash[:value].join(';')}")
    end
  end

  class NotAvailableOnOpenVz < ::StandardError

  end

  class UserNamespaceMapNil < ::StandardError

  end

  class UserNamespaceMapUnchanged < ::StandardError

  end

  class UserNamespaceMapBusy < ::StandardError

  end

  class VpsFeatureConflict < ::StandardError
    # @param f1 [::VpsFeature] f1 conflicts with f2
    # @param f2 [::VpsFeature]
    def initialize(f1, f2)
      super("feature #{f1.name} is in conflict with #{f2.name}, pick one")
    end
  end

  class OsTemplateNotFound < ::StandardError

  end

  class OperationError < ::StandardError

  end

  class OperationNotSupported < OperationError

  end

  class DatasetAlreadyExported < ::StandardError

  end
end
