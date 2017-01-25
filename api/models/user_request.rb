require 'resolv'

class UserRequest < ActiveRecord::Base
  belongs_to :user
  belongs_to :admin, class_name: 'User'

  has_paper_trail

  enum state: %i(awaiting approved denied ignored)

  validates :api_ip_addr, :api_ip_ptr, :state, presence: true

  def self.create!(request, user, input)
    req = new(input)
    req.api_ip_addr = request.ip
    req.api_ip_ptr = req.send(:get_ptr, req.api_ip_addr)

    if request.env['HTTP_CLIENT_IP']
      req.client_ip_addr = request.env['HTTP_CLIENT_IP']
      req.client_ip_ptr = req.send(:get_ptr, req.client_ip_addr)
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
    target_state = {approve: :approved, deny: :denied, ignore: :ignored}[action]

    if target_state == state.to_sym
      errors.add(:state, "is already '#{state}'")
      raise ActiveRecord::RecordInvalid, self
    end

    VpsAdmin::API::Plugins::Requests::TransactionChains::Resolve.fire(
        self,
        target_state,
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

  private
  def get_ptr(ip)
    Resolv.new.getname(ip)

  rescue Resolv::ResolvError => e
    e.message
  end
end
