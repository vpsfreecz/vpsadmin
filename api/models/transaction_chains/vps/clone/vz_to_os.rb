module TransactionChains
  # Clone OpenVZ VPS to new vpsAdminOS VPS
  class Vps::Clone::VzToOs < ::TransactionChain
    label 'Clone'

    include Vps::Clone::Base

    def link_chain(vps, node, attrs)
      lock(vps)
    end
  end
end
