module Transactions::UserNamespace
  class Create < ::Transaction
    t_name :userns_create
    t_type 7001
    queue :general

    def params(node, userns)
      self.node_id = node.id

      {
          name: "u#{userns.id}",
          ugid: userns.ugid,
          offset: userns.offset,
          size: userns.size,
      }
    end
  end
end
