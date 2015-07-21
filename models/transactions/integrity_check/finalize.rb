module Transactions::IntegrityCheck
  class Finalize < ::Transaction
    t_name :integrity_finalize
    t_type 6001

    def params(check)
      self.t_server = transaction_chain.find_node_id
      
      {integrity_check_id: check.id}
    end
  end
end
