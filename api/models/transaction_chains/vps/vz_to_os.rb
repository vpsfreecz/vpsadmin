module TransactionChains
  module Vps::VzToOs
    def replace_os_template(os_template)
      ret = nil

      if os_template.distribution && !os_template.distribution.empty? \
         && os_template.version && !os_template.version.empty?
        dist = os_template.distribution
        ver = os_template.version
      else
        dist, ver = os_template.name.split('-')
      end

      # Exact match
      ret = ::OsTemplate.find_by(
        hypervisor_type: ::OsTemplate.hypervisor_types[:vpsadminos],
        distribution: dist,
        version: ver,
      )
      return ret if ret

      # Match distribution
      ret = ::OsTemplate.where(
        hypervisor_type: ::OsTemplate.hypervisor_types[:vpsadminos],
        distribution: dist,
      ).order('version DESC').take
      return ret if ret

      raise VpsAdmin::API::Exceptions::OsTemplateNotFound,
            "unable to find replacement for OS template #{os_template.label} "+
            "(#{os_template.id})"
    end
  end
end
