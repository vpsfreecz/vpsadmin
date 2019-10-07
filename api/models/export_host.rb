class ExportHost < ::ActiveRecord::Base
  belongs_to :export
  belongs_to :ip_address
end
