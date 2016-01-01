# Transaction chain is a container for multiple transactions.
# Every transaction chain inherits this class. Chains must implement
# method TransactionChain#link_chain.
# All transaction must be in a chain. Transaction without a chain does not
# have a meaning.
class TransactionChain < ActiveRecord::Base
  has_many :transactions
  has_many :transaction_chain_concerns
  belongs_to :user
  belongs_to :user_session

  enum state: %i(staged queued done rollbacking failed fatal resolved)
  enum concern_type: %i(chain_affect chain_transform)

  attr_reader :acquired_locks
  attr_accessor :last_id, :last_node_id, :dst_chain, :named, :locks, :urgent,
                :prio, :mail_server

  include HaveAPI::Hookable

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
      chain.user_session = ::UserSession.current
      chain.urgent_rollback = urgent_rollback? || false
      chain.save

      # link_chain will raise ResourceLocked if it is unable to acquire
      # a lock. It will cause the transaction to be roll backed
      # and the exception will be propagated.
      ret = chain.link_chain(*args)

      if chain.empty?
        if chain.class.allow_empty?
          chain.release_locks
          chain.destroy
          return ret

        else
          fail 'empty'
        end
      end

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
  def self.use_in(chain, args: [], urgent: false, prio: 0, method: :link_chain,
                  hooks: {})
    c = new

    c.last_id = chain.last_id
    c.last_node_id = chain.last_node_id
    c.dst_chain = chain.dst_chain
    c.named = chain.named
    c.locks = chain.locks
    c.urgent = urgent
    c.prio = prio

    hooks.each do |k, v|
      c.connect_hook(k, &v)
    end

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

  def self.allow_empty(allow = true)
    @allow_empty = allow
  end

  def self.allow_empty?
    @allow_empty
  end

  def initialize(*args)
    super(*args)

    @locks = []
    @named = {}
    @dst_chain = self
    @urgent = false
    @prio = 0
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

  # Release all locks acquired by this and all nested chains.
  def release_locks
    @locks.each { |l| l.release }
  end

  # Append transaction of +klass+ with +opts+ to the end of the chain.
  # If +name+ is set, it is used as an anchor which other
  # transaction in chain might hang onto.
  # +args+ and +block+ are forwarded to target transaction.
  # Use the block to configure transaction confirmations, see
  # Transaction::Confirmable.
  # Deprecated in favor of #append_t.
  def append(klass, name: nil, args: [], urgent: nil, prio: nil, &block)
    do_append(@last_id, name, klass, args, urgent, prio, block)
  end

  # This method will be deprecated in the near future.
  # Append transaction of +klass+ with +opts+ to previosly created anchor
  # +dep_name+ instead of the end of the chain.
  # If +name+ is set, it is used as an anchor which other
  # transaction in chain might hang onto.
  # +args+ and +block+ are forwarded to target transaction.
  def append_to(dep_name, klass, name: nil, args: [], urgent: nil, prio: nil, &block)
    do_append(@named[dep_name], name, klass, args, urgent, prio, block)
  end

  # Will replace #append in the future. #append_t does not execute the block
  # in Confirmable instance context, but uses the original context in which
  # the block was defined - +self+ does not change meaning.
  def append_t(klass, name: nil, args: [], urgent: nil, prio: nil, &block)
    do_append(@last_id, name, klass, args, urgent, prio, block, true)
  end

  # Call this method from TransactionChain#link_chain to include
  # +chain+. +args+ are passed to the chain as in ::fire.
  def use_chain(chain, args: [], urgent: nil, prio: nil, method: :link_chain, hooks: {})
    urgent ||= self.urgent
    prio ||= self.prio

    c, ret = chain.use_in(
        self,
        args: args.is_a?(Array) ? args : [args],
        urgent: urgent,
        prio: prio,
        method: method,
        hooks: hooks
    )
    @last_id = c.last_id
    @last_node_id = c.last_node_id
    ret
  end

  def mail(*args)
    m = ::MailTemplate.send_mail!(*args)
    append(Transactions::Mail::Send, args: [find_mail_server, m])
    m.update!(transaction_id: @last_id)
    m
  end

  # Set chain concerns.
  # +type+ can be one of:
  # [affect]     the chain affects these objects
  # [transform]  the chain transforms the first object into another
  #
  # +objects+ is an array of concerned objects. Every object is represented
  # by an array, where the first item is class name, the second is object id.
  # For example: type=transform, objects=[[Vps, 101], [Vps, 102]]
  def concerns(type, *objects)
    # Do not set concerns if this chain is just being used
    # in another one.
    return if dst_chain != self

    self.concern_type = "chain_#{type}"

    objects.each do |obj|
      TransactionChainConcern.create!(
          transaction_chain: self,
          class_name: obj[0],
          row_id: obj[1]
      )
    end
  end

  def format_concerns
    ret = {type: concern_type[6..-1], objects: []}

    transaction_chain_concerns.each do |c|
      ret[:objects] << [c.class_name, c.row_id]
    end

    ret
  end

  # Returns true if the chain is being used (included) by another chain
  # using method self.use_chain.
  def included?
    @dst_chain != self
  end

  def empty?
    size == 0
  end

  def label
    Kernel.const_get(type).label
  end

  # Return the node ID of last transaction. Find first available server if no
  # transactions have been appended yet.
  def find_node_id
    if @last_node_id
      @last_node_id

    else
      @last_node_id = ::Node.first_available.id
    end
  end

  private
  def do_append(dep, name, klass, args, urgent, prio, block, retain_context = false)
    args = [args] unless args.is_a?(Array)

    urgent ||= self.urgent
    prio ||= self.prio

    @dst_chain.size += 1
    t = klass.fire_chained(@dst_chain, dep, urgent, prio, retain_context, *args, &block)
    @last_node_id = t.t_server
    @last_id = t.id
    @named[name] = @last_id if name
    @last_id
  end

  def find_mail_server
    chain = dst_chain || self
    return chain.mail_server if chain.mail_server

    chain.mail_server = ::Node.find_by(server_type: 'mailer')
    chain.mail_server ||= ::Node.order('server_id').take!
  end
end

module TransactionChains
  module Cluster        ; end
  module Node           ; end
  module Vps            ; end
  module VpsConfig      ; end
  module Ip             ; end
  module Pool           ; end
  module Dataset        ; end
  module DatasetInPool  ; end
  module Snapshot       ; end
  module SnapshotInPool ; end
  module DatasetTree    ; end
  module Branch         ; end
  module User           ; end
  module Lifetimes      ; end
  module DnsResolver    ; end
  module Mail           ; end
  module IntegrityCheck ; end
end
