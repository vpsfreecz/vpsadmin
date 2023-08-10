class Mailbox < ActiveRecord::Base
  has_many :mailbox_handlers, dependent: :delete_all
end
