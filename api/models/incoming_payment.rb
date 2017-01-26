class IncomingPayment < ActiveRecord::Base
  enum state: %i(queued unmatched processed ignored)
end
