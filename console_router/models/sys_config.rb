class SysConfig < ::ActiveRecord::Base
  self.table_name = 'sysconfig'

  serialize :value, JSON
end
