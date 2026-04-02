module VpsAdmin::API
  module Operations::Utils::PoolSpace
    module_function

    def template_refquota!(os_template:, diskspace:, lookup_name:)
      tpl_ds = os_template.datasets.detect { |v| v['name'] == lookup_name } || {}
      refquota = tpl_ds.dig('properties', 'refquota')

      if refquota.nil?
        return diskspace if lookup_name == '/'

        raise VpsAdmin::API::Exceptions::OperationError,
              "OS template #{os_template.label} is missing refquota option for dataset #{lookup_name}"
      end

      return refquota if refquota.is_a?(Integer)

      if /\A(\d+)%\z/ =~ refquota
        return (diskspace / 100.0 * Regexp.last_match(1).to_i).floor
      end

      raise VpsAdmin::API::Exceptions::OperationError,
            "OS template #{os_template.label} has unknown refquota format: #{refquota.inspect}"
    end

    def required_new_vps_diskspace!(os_template:, diskspace:)
      os_template.datasets.sum do |ds|
        template_refquota!(
          os_template:,
          diskspace:,
          lookup_name: ds['name']
        )
      end + (
        os_template.datasets.any? { |ds| ds['name'] == '/' } ? 0 : diskspace
      )
    end

    def default_vps_diskspace!(environment:)
      if environment.nil?
        raise VpsAdmin::API::Exceptions::OperationError,
              'unable to determine environment for default VPS diskspace'
      end

      ::DefaultObjectClusterResource.joins(:cluster_resource).find_by!(
        environment:,
        class_name: 'Vps',
        cluster_resources: { name: 'diskspace' }
      ).value
    rescue ActiveRecord::RecordNotFound
      raise VpsAdmin::API::Exceptions::OperationError,
            "default VPS diskspace is not configured in environment #{environment.label}"
    end

    def required_default_new_vps_diskspace!(environment:, os_template:)
      diskspace = default_vps_diskspace!(environment:)

      required_new_vps_diskspace!(
        os_template:,
        diskspace:
      )
    end

    def required_dataset_tree_diskspace(root_dip)
      ([root_dip] + root_dip.subdatasets_in_pool).uniq.sum(&:diskspace)
    end
  end
end
