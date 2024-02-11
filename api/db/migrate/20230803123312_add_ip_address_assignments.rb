class AddIpAddressAssignments < ActiveRecord::Migration[7.0]
  IpInfo = Struct.new(
    :log,
    :record,
    keyword_init: true
  ) do
    def id
      record.id
    end

    def user_id
      @user_id ||=
        if record.user_id
          record.user_id
        elsif record.network_interface
          record.network_interface.vps.user_id
        end
    end

    def vps_id
      @vps_id ||= record.network_interface ? record.network_interface.vps_id : nil
    end
  end

  class Network < ActiveRecord::Base
    has_many :ip_addresses
  end

  class NetworkInterface < ActiveRecord::Base
    belongs_to :vps
    has_many :ip_addresses
  end

  class IpAddress < ActiveRecord::Base
    belongs_to :network
    belongs_to :network_interface
  end

  class IpAddressAssignment < ActiveRecord::Base; end

  class Transaction < ActiveRecord::Base
    belongs_to :transaction_chain
  end

  class TransactionChain < ActiveRecord::Base
    has_many :transactions
  end

  class Vps < ActiveRecord::Base
    belongs_to :user
    has_many :network_interfaces
  end

  class User < ActiveRecord::Base
    has_many :vpses
  end

  def change
    create_table :ip_address_assignments do |t|
      t.references  :ip_address,                   null: false
      t.string      :ip_addr,                      null: false, limit: 40
      t.integer     :ip_prefix,                    null: false
      t.references  :user,                         null: false
      t.references  :vps,                          null: false
      t.datetime    :from_date,                    null: false
      t.datetime    :to_date,                      null: true
      t.references  :assigned_by_chain,            null: true
      t.references  :unassigned_by_chain,          null: true
      t.boolean     :reconstructed,                null: false, default: false
      t.timestamps                                 null: false
    end

    add_index :ip_address_assignments, :ip_addr
    add_index :ip_address_assignments, :ip_prefix
    add_index :ip_address_assignments, :from_date
    add_index :ip_address_assignments, :to_date

    reversible do |dir|
      dir.up do
        reconstruct_assignments
      end
    end
  end

  protected

  # Reconstruct IP address assignment history from transactions
  #
  # When this migration is run, we know the current state of affairs. In order
  # to recover past assignments and make the log useful, we walk through
  # transactions, AddRoute/DelRoute transactions in particular. From these we
  # can deduce when and for how long were IP addresses assigned. It should handle
  # most cases, but it is not perfect: we do not account for VPS chowns and
  # replacements, etc.
  #
  # The transaction database however did not exist from the start, so pre mid-2015
  # assignments cannot be recovered.
  def reconstruct_assignments
    vpses = {}

    Vps.all.each do |vps|
      vpses[vps.id] = vps
    end

    ips = {}

    IpAddress
      .includes(:network, network_interface: :vps)
      .joins(:network)
      .where(networks: { purpose: [0, 1] }) # only vps networks
      .each do |ip|
      ips[ip.ip_addr] = IpInfo.new(
        log: [],
        record: ip
      )
    end

    # Walk through AddRoute/DelRoute transactions
    Transaction
      .joins(:transaction_chain)
      .where(handle: [2006, 2007])
      .where(
        '(transaction_chains.state IN (2, 4) AND transactions.done = 1 AND transactions.status = 1)
        OR
        (transaction_chains.state = 6)'
      )
      .order('id').each do |trans|
      t_input = JSON.parse(trans.input)
      addr =
        if t_input.has_key?('input') && t_input.has_key?('handle')
          t_input.fetch('input').fetch('addr')
        else
          t_input.fetch('addr')
        end

      ip = ips[addr]

      if ip.nil?
        warn "IP #{addr} not found in DB, ignoring"
        next
      end

      vps = vpses[trans.vps_id]

      if vps.nil?
        warn "VPS #{trans.vps_id} not found in DB, ignoring"
        next
      end

      case trans.handle
      when 2006 # AddRoute
        if ip.log.any? && ip.log.last.to_date.nil?
          # Seems like we're missing a previous DelRoute
          ip.log.last.to_date = trans.finished_at || trans.created_at
          ip.log.last.unassigned_by_chain_id = trans.transaction_chain_id
        end

        ip.log << IpAddressAssignment.new(
          ip_address_id: ip.id,
          ip_addr: ip.record.ip_addr,
          ip_prefix: ip.record.prefix,
          user_id: vps.user_id,
          vps_id: vps.id,
          from_date: trans.finished_at || trans.created_at,
          to_date: nil,
          assigned_by_chain_id: trans.transaction_chain_id,
          reconstructed: true
        )

      when 2007 # DelRoute
        if ip.log.empty?
          # We have not seen the IP being added, which means it was added before
          # vpsAdmin transactions can remember. We therefore assume it was assigned
          # to the VPS when it was created, which in some instances may not be true.
          ip.log << IpAddressAssignment.new(
            ip_address_id: ip.id,
            ip_addr: ip.record.ip_addr,
            ip_prefix: ip.record.prefix,
            user_id: vps.user_id,
            vps_id: vps.id,
            from_date: vps.created_at,
            to_date: trans.finished_at || trans.created_at,
            reconstructed: true
          )
        elsif ip.log.last.to_date.nil?
          ip.log.last.to_date = trans.finished_at || trans.created_at
          ip.log.last.unassigned_by_chain_id = trans.transaction_chain_id
        end
      end
    end

    # Ensure all assignments exist by walking through current ownerships
    ips.each_value do |ip|
      if ip.log.empty? && ip.vps_id
        # We didn't find the transaction that would add the IP, but it is assigned
        ip.log << IpAddressAssignment.new(
          ip_address_id: ip.id,
          ip_addr: ip.record.ip_addr,
          ip_prefix: ip.record.prefix,
          user_id: ip.user_id,
          vps_id: ip.vps_id,
          from_date: Time.now,
          to_date: nil,
          reconstructed: true
        )

        next
      end

      last = ip.log.last

      if last && last.to_date && ip.vps_id
        # We found some assignment in the past, but not the current one
        ip.log << IpAddressAssignment.new(
          ip_address_id: ip.id,
          ip_addr: ip.record.ip_addr,
          ip_prefix: ip.record.prefix,
          user_id: ip.user_id,
          vps_id: ip.vps_id,
          from_date: Time.now,
          to_date: nil,
          reconstructed: true
        )

        next
      end

      next unless last && last.to_date.nil? && ip.vps_id && (last.user_id != ip.user_id || last.vps_id != ip.vps_id)

      # There is an assignment, but the current user/vps is different
      last.to_date = Time.now

      ip.log << IpAddressAssignment.new(
        ip_address_id: ip.id,
        ip_addr: ip.record.ip_addr,
        ip_prefix: ip.record.prefix,
        user_id: ip.user_id,
        vps_id: ip.vps_id,
        from_date: Time.now,
        to_date: nil,
        reconstructed: true
      )

      next
    end

    # Save all assignments
    ips.each_value do |ip|
      ip.log.each(&:save!)
    end
  end
end
