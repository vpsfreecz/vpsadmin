class SysConfig < ActiveRecord::Base
  self.table_name = 'sysconfig'

  serialize :cfg_value, JSON

  validates :cfg_name, presence: true

  alias_attribute :name, :cfg_name
  alias_attribute :value, :cfg_value

  def self.get(k)
    obj = find_by(cfg_name: k)
    obj.value if obj
  end

  def self.set(k, v)
    SysConfig.transaction do
      obj = find_by(cfg_name: k)

      if obj
        obj.update!(cfg_value: v)
      else
        new(cfg_name: k.to_s, cfg_value: v).save!
      end
    end
  end
end
