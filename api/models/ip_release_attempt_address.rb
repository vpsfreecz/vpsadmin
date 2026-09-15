class IpReleaseAttemptAddress < ApplicationRecord
  belongs_to :ip_release_attempt
  belongs_to :ip_release_request_address
end
