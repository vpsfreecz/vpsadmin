class IncomingPayment < ActiveRecord::Base
  enum state: %i(unmatched processed ignored)
end
