class OutageSecurityAdvisory < ApplicationRecord
  belongs_to :outage
  belongs_to :security_advisory
end

class Outage
  has_many :outage_security_advisories, dependent: :delete_all
  has_many :security_advisories, through: :outage_security_advisories
end

class SecurityAdvisory
  has_many :outage_security_advisories, dependent: :delete_all
  has_many :outages, through: :outage_security_advisories
end
