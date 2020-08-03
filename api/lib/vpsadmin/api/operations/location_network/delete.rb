require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::LocationNetwork::Delete < Operations::Base
    # @param ln [::LocationNetwork]
    def run(ln)
      ActiveRecord::Base.transaction do
        ln.network.update!(location: nil) if ln.primary
        ln.destroy!
      end
    end
  end
end
