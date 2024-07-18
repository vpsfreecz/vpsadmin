require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::DnsTsigKey::Destroy < Operations::Base
    # @param tsig_key [::DnsTsigKey]
    def run(tsig_key)
      tsig_key.destroy!
    end
  end
end
