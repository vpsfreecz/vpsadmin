class NewsLog < ActiveRecord::Base
  validates :message, :published_at, presence: true
end
