class LocationNetwork < ::ActiveRecord::Base
  belongs_to :location
  belongs_to :network
end
