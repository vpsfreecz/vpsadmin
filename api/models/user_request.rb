require 'resolv'

class UserRequest < ActiveRecord::Base
  belongs_to :user
  belongs_to :admin, class_name: 'User'

  has_paper_trail

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
    req.save!

    VpsAdmin::API::Plugins::Requests::TransactionChains::Create.fire(req)
    req
  end

  def user_mail
    user.email
  end

  def user_language
    user.language
  end

  def type_name
    self.class.name.demodulize.underscore
  end

  def resolve(action, reason, params)
    VpsAdmin::API::Plugins::Requests::TransactionChains::Resolve.fire(
        self,
        {approve: :approved, deny: :denied, ignore: :ignored}[action],
        action,
        reason,
        params,
    )
  end

  def approve(chain, params)

  end

  def deny(chain, params)

  end

  def ignore(chain, params)

  end

  def invalidate(chain, params)

  end
end
