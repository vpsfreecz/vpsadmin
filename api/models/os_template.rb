class OsTemplate < ActiveRecord::Base
  #has_many :environment_os_templates
  #has_many :environments, through: :environment_os_templates
  has_many :vpses
  enum hypervisor_type: %i(openvz vpsadminos)

  def enabled?
    enabled
  end

  def in_use?
    ::Vps.including_deleted.exists?(os_template: self)
  end
end
