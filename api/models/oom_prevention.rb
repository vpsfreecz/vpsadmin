class OomPrevention < ApplicationRecord
  belongs_to :vps
  enum :action, %i[restart stop]
end
