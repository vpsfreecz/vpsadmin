class NewsLog < ApplicationRecord
  validates :message, :published_at, presence: true
end
