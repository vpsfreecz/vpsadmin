# Transaction chain is a container for multiple transactions.
# Every transaction chain inherits this class. Chains must implement
# method TransactionChain#link_chain.
# All transaction must be in a chain. Transaction without a chain does not
# have a meaning.
class TransactionChain < ActiveRecord::Base
  has_many :transactions
  belongs_to :user

  enum state: %i(staged queued done rollbacking failed)

  attr_reader :acquired_locks
  attr_accessor :last_id, :dst_chain, :named, :locks, :urgent

  # Create new transaction chain. This method has to be used, do not
  # create instances of TransactionChain yourself.
  # All arguments are passed to TransactionChain#link_chain.
  def self.fire(*args)
    ret = nil

    TransactionChain.transaction do
      chain = new
      chain.name = chain_name
      chain.state = :staged
      chain.size = 0
      chain.user = User.current
      chain.urgent_rollback = urgent_rollback? || false
      chain.save

      # link_chain will raise ResourceLocked if it is unable to acquire
      # a lock. It will cause the transaction to be roll backed
      # and the exception will be propagated.
      ret = chain.link_chain(*args)

      fail 'empty' if chain.empty?

      chain.state = :queued
      chain.save
    end

    ret
  end

  # The chain name is a class name in lowercase with added
  # underscores.
  def self.chain_name
    self.to_s.demodulize.underscore
  end

  # Include this chain in +chain+. All remaining arguments are passed
  # to #link_chain.
  # Method #link_chain is called in the same way as in ::fire,
  # except that all transactions are appended to +chain+,
  # not to instance of self.
  # This method should not be called directly, but via #use_chain.
  def self.use_in(chain, args: [], urgent: false, method: :link_chain)
    c = new

    c.last_id = chain.last_id
    c.dst_chain = chain.dst_chain
    c.named = chain.named
    c.locks = chain.locks
    c.urgent = urgent

    ret = c.send(method, *args)

    [c, ret]
  end

  # Set a human-friendly label for the chain.
  def self.label(v = nil)
    if v
      @label = v
    else
      @label
    end
  end

  # If set, when doing a rollback of this chain, all transactions
  # will be considered as urgent.
  def self.urgent_rollback(urgent = true)
    @urgent_rollback = urgent
  end

  def self.urgent_rollback?
    @urgent_rollback
  end

  def initialize(*args)
    super(*args)

    @locks = []
    @named = {}
    @dst_chain = self
    @urgent = false
  end

  # All chains must implement this method.
  def link_chain(*args)
    raise NotImplementedError
  end

  # Helper method for acquiring resource locks. TransactionChain remembers
  # what locks it has, therefore it is safe to lock one resource more than
  # once, which happens when including other chains with ::use_in.
  def lock(obj, *args)
    return if @locks.detect { |l| l.locks?(obj) }

    @locks << obj.acquire_lock(@dst_chain, *args)
  end

  # Append transaction of +klass+ with +opts+ to the end of the chain.
  # If +name+ is set, it is used as an anchor which other
  # transaction in chain might hang onto.
  # +args+ and +block+ are forwarded to target transaction.
  # Use the block to configure transaction confirmations, see
  # Transaction::Confirmable.
  def append(klass, name: nil, args: [], urgent: nil, &block)
    do_append(@last_id, name, klass, args, urgent, block)
  end

  # This method will be deprecated in the near future.
  # Append transaction of +klass+ with +opts+ to previosly created anchor
  # +dep_name+ instead of the end of the chain.
  # If +name+ is set, it is used as an anchor which other
  # transaction in chain might hang onto.
  # +args+ and +block+ are forwarded to target transaction.
  def append_to(dep_name, klass, name: nil, args: [], urgent: nil, &block)
    do_append(@named[dep_name], name, klass, args, urgent, block)
  end

  # Call this method from TransactionChain#link_chain to include
  # +chain+. +args+ are passed to the chain as in ::fire.
  def use_chain(chain, args: [], urgent: false, method: :link_chain)
    c, ret = chain.use_in(
        self,
        args: args.is_a?(Array) ? args : [args],
        urgent: urgent,
        method: method
    )
    @last_id = c.last_id
    ret
  end

  def empty?
    size == 0
  end

  def label
    Kernel.const_get(type).label
  end

  private
  def do_append(dep, name, klass, args, urgent, block)
    args = [args] unless args.is_a?(Array)

    urgent ||= self.urgent

    @dst_chain.size += 1
    @last_id = klass.fire_chained(@dst_chain, dep, urgent, *args, &block)
    @named[name] = @last_id if name
    @last_id
  end
end

module TransactionChains
  module Node           ; end
  module Vps            ; end
  module VpsConfig      ; end
  module Ip             ; end
  module Pool           ; end
  module Dataset        ; end
  module DatasetInPool  ; end
  module SnapshotInPool ; end
  module DatasetTree    ; end
  module Branch         ; end
  module User           ; end
end
