require 'resolv'

class UserRequest < ActiveRecord::Base
  belongs_to :user
  belongs_to :admin, class_name: 'User'

  enum state: %i(awaiting approved denied ignored)

  validates :ip_addr, :ip_addr_ptr, :state, presence: true

  def self.create!(request, user, input)
    req = new(input)
    req.ip_addr = request.ip

    begin
      req.ip_addr_ptr = Resolv.new.getname(req.ip_addr)

    rescue Resolv::ResolvError => e
      req.ip_addr_ptr = e.message
    end

    req.user = user

    # TODO: transaction chain to send mails

    req.save!
    req
  end

  def approve

  end

  def deny

  end

  def ignore

  end

  def invalidate

  end
end
