class Mailbox < ApplicationRecord
  has_many :mailbox_handlers, dependent: :delete_all
end
