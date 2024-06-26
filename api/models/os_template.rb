class OsTemplate < ApplicationRecord
  # has_many :environment_os_templates
  # has_many :environments, through: :environment_os_templates
  has_many :vpses
  enum hypervisor_type: %i[openvz vpsadminos]
  enum cgroup_version: %i[cgroup_any cgroup_v1 cgroup_v2]

  before_save :set_name

  def enabled?
    enabled
  end

  def in_use?
    ::Vps.including_deleted.exists?(os_template: self)
  end

  protected

  def set_name
    self.name = [distribution, version, arch, vendor, variant].join('-')
  end
end
