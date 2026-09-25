# The freeze row serializes new storage writers with a switch to read_only.
# Call while staging a chain, in the same SQL transaction as its writes.
class StorageMutationAdmission
  def self.check!
    unless StorageFreezeControl.connection.transaction_open?
      raise 'storage mutation admission requires a staging transaction'
    end

    control = StorageFreezeControl.lock.find(1)
    return control if control.read_write?

    raise VpsAdmin::API::Exceptions::StorageReadOnly
  end
end
