class OomReportRule < ApplicationRecord
  belongs_to :vps
  has_many :oom_reports, dependent: :nullify

  enum :action, %i[notify ignore]

  validates :action, presence: true
  validates :cgroup_pattern, presence: true, length: { maximum: 255 }

  def label
    max_len = 30
    pattern =
      if cgroup_pattern.length > max_len
        "#{cgroup_pattern[0..(max_len - 1)]}..."
      else
        cgroup_pattern
      end

    "#{action} #{pattern}"
  end
end
