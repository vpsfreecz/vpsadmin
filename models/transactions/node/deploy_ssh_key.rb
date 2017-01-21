module Transactions::Node
  class DeploySshKey < ::Transaction
    t_name :node_deploy_ssh_key
    t_type 7

    def params(node)
      self.node_id = node.id

      {
          public_key: SysConfig.get('node', 'public_key'),
          private_key: SysConfig.get('node', 'private_key'),
          key_type: SysConfig.get('node', 'key_type'),
      }
    end
  end
end
