module TransactionChains
  class Deprecated < ::TransactionChain
    label 'Deprecated'

    def link_chain(*_)
      raise "Transaction chain #{self.class.name} has been deprecated"
    end
  end

  module Dataset
    class SetUserNamespaceMap < Deprecated
      label 'Set user namespace map'
    end
  end

  module Vps
    class ApplyConfig < Deprecated
      label 'Apply config'
    end

    class AddIp < Deprecated
      label 'Add IP'
    end

    class DelIp < Deprecated
      label 'Delete IP'
    end

    class CreateVeth < Deprecated
      label 'Create veth'
    end

    class RemoveVeth < Deprecated
      label 'Remove veth'
    end

    class SetUserNamespaceMap < Deprecated
      label 'Set user namespace map'
    end

    class ShaperChange < Deprecated
      label 'Change shaper'
    end

    class ShaperSet < Deprecated
      label 'Set shaper'
    end

    class ShaperUnset < Deprecated
      label 'Unset shaper'
    end

    class MountSnapshot < Deprecated
      label 'Mount snapshot'
    end

    class UmountSnapshot < Deprecated
      label 'Unmount snapshot'
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
    class Cluster < Deprecated
      label 'Integrity check cluster'
    end

    class Node < Deprecated
      label 'Integrity check node'
    end
  end

  module Cluster
    class GenerateKnownHosts < Deprecated
      label 'Known hosts'
    end
  end
end
