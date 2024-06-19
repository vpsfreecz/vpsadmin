class ExportHost < ApplicationRecord
  belongs_to :export
  belongs_to :ip_address
end
