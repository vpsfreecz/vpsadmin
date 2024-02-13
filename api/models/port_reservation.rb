class PortReservation < ActiveRecord::Base
  belongs_to :node
  belongs_to :transaction_chain

  def self.reserve(node, addr, chain)
    where(node: node, addr: nil).order('port ASC').limit(10).each do |r|
      r.update!(addr: addr, transaction_chain: chain)
      return r
    rescue ActiveRecord::RecordNotUnique
      next
    end

    raise 'no port available'
  end

  def free
    update!(addr: nil, transaction_chain: nil)
  end
end
