class OomPrevention < ActiveRecord::Base
  belongs_to :vps
  enum action: %i[restart stop]
end
