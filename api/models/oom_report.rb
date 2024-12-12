class OomReport < ApplicationRecord
  belongs_to :vps
  belongs_to :oom_report_rule
  has_many :oom_report_usages, dependent: :delete_all
  has_many :oom_report_stats, dependent: :delete_all
  has_many :oom_report_tasks, dependent: :delete_all

  default_scope { where(processed: true) }
end
