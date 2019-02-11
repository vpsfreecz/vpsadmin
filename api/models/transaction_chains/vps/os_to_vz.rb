module TransactionChains
  module Vps::OsToVz
    def replace_os_template(os_template)
      ret = nil

      # Exact match
      ret = ::OsTemplate.where(
        hypervisor_type: ::OsTemplate.hypervisor_types[:openvz],
      ).where(
        "name LIKE ?",
        "#{os_template.distribution}-#{os_template.version}-#{os_template.arch}-%"
      ).take
      return ret if ret

      # Match distribution
      ret = ::OsTemplate.where(
        hypervisor_type: ::OsTemplate.hypervisor_types[:openvz],
      ).where(
        "name LIKE ?",
        "#{os_template.distribution}-%"
      ).order('version DESC').take
      return ret if ret

      raise VpsAdmin::API::Exceptions::OsTemplateNotFound,
            "unable to find replacement for OS template #{os_template.label} "+
            "(#{os_template.id})"
    end
  end
end
