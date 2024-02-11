module TransactionChains
  class Deprecated < ::TransactionChain
    def link_chain(*_)
      raise "Transaction chain #{self.class.name} has been deprecated"
    end
  end

  module Dataset
    class SetUserNamespaceMap < Deprecated; end
  end

  module Vps
    class ApplyConfig < Deprecated
      label 'Apply config'
    end

    class AddIp < Deprecated; end
    class DelIp < Deprecated; end
    class CreateVeth < Deprecated; end
    class RemoveVeth < Deprecated; end

    class SetUserNamespaceMap < Deprecated; end

    class ShaperChange < Deprecated; end
    class ShaperSet < Deprecated; end
    class ShaperUnset < Deprecated; end

    class MountSnapshot < Deprecated
      label 'Mount snapshot'
    end

    class UmountSnapshot < Deprecated
      label 'Unount snapshot'
    end

    module Clone
      class VzToOs < Deprecated
        label 'Clone'
      end

      class VzToVz < Deprecated
        label 'Clone'
      end
    end

    module Migrate
      class OsToVz < Deprecated
        label 'Migrate'
      end

      class VzToOs < Deprecated
        label 'Migrate'
      end

      class VzToVz < Deprecated
        label 'Migrate'
      end
    end
  end

  module VpsConfig
    class Create < Deprecated
      label 'Create'
    end

    class Delete < Deprecated
      label 'Delete'
    end

    class Update < Deprecated
      label 'Update'
    end
  end

  module IntegrityCheck
    class Cluster < Deprecated; end
    class Node < Deprecated; end
  end
end
