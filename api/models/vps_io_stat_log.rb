class VpsIoStatLog < ApplicationRecord
  belongs_to :vps
  belongs_to :storage_volume
end
