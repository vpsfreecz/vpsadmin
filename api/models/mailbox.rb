class Mailbox < ApplicationRecord
  event_delete_cascades :mailbox_handlers
  has_many :mailbox_handlers, dependent: :delete_all
end
