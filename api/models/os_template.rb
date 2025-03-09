class OsTemplate < ApplicationRecord
  belongs_to :os_family
  has_many :vpses
  enum :hypervisor_type, %i[openvz vpsadminos]
  enum :cgroup_version, %i[cgroup_any cgroup_v1 cgroup_v2]
  serialize :config, coder: YAML

  before_save :set_name

  def enabled?
    enabled
  end

  def in_use?
    ::Vps.including_deleted.exists?(os_template: self)
  end

  # @return [Array<Hash>]
  def datasets
    return [] if config.nil?

    config.fetch('datasets', [])
  end

  # @return [Array<Hash>]
  def mounts
    return [] if config.nil?

    config.fetch('mounts', [])
  end

  # @return [Hash<String, Boolean>]
  def features
    return {} if config.nil?

    config.fetch('features', {})
  end

  def config_string
    YAML.dump(config)
  end

  # @param user_data [::VpsUserData]
  def support_user_data?(user_data)
    case user_data.format
    when 'script'
      enable_script
    when 'cloudinit_config', 'cloudinit_script'
      enable_cloud_init
    else
      false
    end
  end

  protected

  def set_name
    self.name = [distribution, version, arch, vendor, variant].join('-')
  end
end
