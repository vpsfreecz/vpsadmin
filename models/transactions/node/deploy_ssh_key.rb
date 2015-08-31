module Transactions::Node
  class DeploySshKey < ::Transaction
    t_name :node_deploy_ssh_key
    t_type 7

    def params(node)
      self.t_server = node.id

      {
          public_key: SysConfig.get('node_public_key'),
          private_key: SysConfig.get('node_private_key'),
          key_type: SysConfig.get('node_key_type')
      }
    end
  end
end
