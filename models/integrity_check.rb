class IntegrityCheck < ActiveRecord::Base
  belongs_to :user
  enum status: %i(pending integral broken)

  def self.schedule(opts)
    modules = []

    modules << :storage if opts[:storage] 
    modules << :vps if opts[:vps]

    if opts[:node]
      TransactionChains::IntegrityCheck::Node.fire(nil, opts[:node], modules)
    else
      TransactionChains::IntegrityCheck::Cluster.fire(opts, modules)
    end
  end
end
