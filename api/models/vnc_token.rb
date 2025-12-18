class VncToken < ApplicationRecord
  belongs_to :user_session
  belongs_to :vps
  belongs_to :client_token, class_name: 'Token'
  belongs_to :node_token, class_name: 'Token'

  def self.find_for(vps, user_session)
    where(vps:, user_session:)
      .where('expiration > ?', Time.now)
      .where.not(client_token: nil)
      .where.not(node_token: nil)
      .take
  end

  def self.create_for!(vps, user_session)
    vnc_token = new(
      vps:,
      user_session:,
      expiration: Time.now + 60
    )

    ::Token.for_new_record!(vnc_token.expiration, count: 2) do |t1, t2|
      vnc_token.client_token = t1
      vnc_token.node_token = t2
      vnc_token.save!
      vnc_token
    end

    vnc_token
  end

  def extend!
    transaction do
      new_expiration = Time.now + 60

      [client_token, node_token].each do |t|
        next if t.nil?

        t.update!(valid_to: new_expiration)
      end

      update!(expiration: new_expiration)
    end
  end

  def expire!
    update!(
      client_token: nil,
      node_token: nil
    )
  end

  def client_token_str
    client_token.to_s
  end
end
