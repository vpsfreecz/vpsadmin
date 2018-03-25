module Transactions::UserNamespace
  class Destroy < ::Transaction
    t_name :userns_destroy
    t_type 7002
    queue :general

    def params(node, userns)
      self.node_id = node.id

      {
          name: userns.id.to_s,
          ugid: userns.ugid,
          offset: userns.offset,
          size: userns.size,
      }
    end
  end
end
