class IntegrityCheck < ActiveRecord::Base
  belongs_to :user
  enum status: %i(pending integral broken)

  def self.schedule(opts)
    modules = []

    if opts[:storage]
      modules << :storage

    elsif opts[:vps]
      modules << :vps
    end

    if opts[:node]
      TransactionChains::IntegrityCheck::Node.fire(nil, opts[:node], modules)
    else
      TransactionChains::IntegrityCheck::Cluster.fire(modules)
    end
  end
end
