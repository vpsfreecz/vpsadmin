class OsTemplate < ActiveRecord::Base
  self.table_name = 'cfg_templates'
  self.primary_key = 'templ_id'

  #has_many :environment_os_templates
  #has_many :environments, through: :environment_os_templates
  has_many :vpses, :foreign_key => :vps_template
  has_paper_trail

  alias_attribute :label, :templ_label
  alias_attribute :name, :templ_name

  def enabled?
    templ_enabled
  end

  def in_use?
    ::Vps.including_deleted.exists?(os_template: self)
  end
end
