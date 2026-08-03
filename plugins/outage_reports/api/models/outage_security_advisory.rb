class OutageSecurityAdvisory < ApplicationRecord
  belongs_to :outage
  belongs_to :security_advisory

  validates :outage, :security_advisory, presence: true
  validates :security_advisory_id, uniqueness: { scope: :outage_id }
end

class Outage
  event_delete_cascades :outage_security_advisories
  has_many :outage_security_advisories, dependent: :delete_all
  has_many :security_advisories, through: :outage_security_advisories
end

class SecurityAdvisory
  event_delete_cascades :outage_security_advisories
  has_many :outage_security_advisories, dependent: :delete_all
  has_many :outages, through: :outage_security_advisories
end
