class ExportMount < ApplicationRecord
  belongs_to :export
  belongs_to :vps
end
