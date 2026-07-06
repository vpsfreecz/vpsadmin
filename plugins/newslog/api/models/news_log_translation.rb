class NewsLogTranslation < ApplicationRecord
  belongs_to :news_log
  belongs_to :language

  validates :message, presence: true
end
