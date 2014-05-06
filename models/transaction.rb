# General transaction. Should be inherited for concrete use. This is just basic
# inheritance, no ActiveRecord inheritance necessary.
# Subclasses must implement method #prepare.
# Subclass can also define following attributes:
# [t_name]    a name for this transaction for future referencing, symbol
# [t_type]    numeric code as recognized in vpsAdmin
# [t_chain]   is this a single transaction or a chain of transactions? boolean
class Transaction < ActiveRecord::Base
  self.primary_key = 't_id'

  references :user, foreign_key: :t_m_id
  references :node, foreign_key: :t_server
  references :vps, foreignKey: :t_vps

  before_save :set_init_values

  class << self
    def t_name(name=nil)
      if name
        @name = name
      else
        @name
      end
    end

    def t_type(t=nil)
      if t
        @t_type = t
      else
        @t_type
      end
    end

    def t_chain(chain=nil)
      if chain
        @chain = chain
      else
        @chain
      end
    end
  end

  # Construct transaction chain.
  # Chained transactions depends on each other. In case a transaction fails,
  # all transactions that depends on it fail too.
  # Chain is defined by +block+. It is run in context of Transaction::Chain.
  # Transactions are linked together by Chain#append and Chain#append_to.
  def self.chain(&block)
    chain = Chain.new
    chain.exec(&block)
  end

  # Enqueue transaction. This class method must be called on appropriate
  # subclass, not on Transaction itself.
  # Subclasses must implement method prepare, which should return a hash
  # of parameters.
  def self.fire(*args)
    t = new

    if t_chain
      return t.prepare(*args)
    end

    t.t_type = t.class.t_type if t.class.t_type
    t.t_param = (t.prepare(*args) || {}).to_json

    t.save!
    t.t_id
  end

  # Set default values for start time, success, done and user id.
  def set_init_values
    self.t_time = Time.new.to_i
    self.t_success = 0
    self.t_done = 0
    self.t_m_id = User.current.m_id
  end

  # Must be implemented in subclasses.
  # Returns hash of parameters for single transaction. If target transaction
  # is chained, return the ID of last transaction in chain.
  def prepare(*args)
    raise NotImplementedError
  end

  # Class for chaining transactions. Should not be created directly, but by
  # Transaction.chain.
  class Chain
    # Create new chain. +dep+ is an initi al dependency using which it is
    # possible to chain chains.
    def initialize(dep=nil)
      @named = {}
      @last_id = dep
    end

    # Execute giben block in the context of this chain.
    def exec(&block)
      ::Transaction.transaction do
        instance_eval(&block)
      end

      @last_id
    end

    # Append transaction of +klass+ with +opts+ to the end of the chain.
    # If +opts+ contains key +:name+, it is used as an anchor which other
    # transaction in chain might hang onto.
    def append(klass, opts)
      do_append(@last_id, klass, opts)
    end

    # Append transaction of +klass+ with +opts+ to previosly created anchor
    # +name+ instead of the end of the chain.
    def append_to(name, klass, opts)
      do_append(@named[name], klass, opts)
    end

    private
    def do_append(dep, klass, opts)
      opts[:t_depends_on] = dep
      @last_id = klass.fire(opts) # fixme might have to remove +name+
      @named[name] = @last_id if opts[:name]
      @last_id
    end
  end
end

module Transactions
  module Vps

  end
end
