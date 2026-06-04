class SecurityAdvisoryCve < ApplicationRecord
  belongs_to :security_advisory

  validates :cve_id, presence: true,
                     format: {
                       with: /\ACVE-\d{4}-\d{4,}\z/,
                       message: 'must be in CVE-YYYY-NNNN format'
                     },
                     uniqueness: { scope: :security_advisory_id }

  before_validation :normalize_cve_id

  def url
    "https://www.cve.org/CVERecord?id=#{cve_id}"
  end

  protected

  def normalize_cve_id
    self.cve_id = ::SecurityAdvisory.normalize_cve(cve_id)
  end
end
