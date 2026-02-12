class LocationNetwork < ApplicationRecord
  belongs_to :location
  belongs_to :network

  validates :location, presence: true
  validates :network, presence: true

  # There's a unique index on primary, we want it to be set either to `true`
  # or to `nil`, so that there could be multiple non-primary records.
  before_save :nillify_primary

  protected

  def nillify_primary
    self.primary = nil if primary === false
  end
end
