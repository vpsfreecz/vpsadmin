# General transaction. Should be inherited for concrete use. This is just basic
# inheritance, no ActiveRecord inheritance necessary.
# Subclasses must implement method #prepare.
# Subclass can also define following attributes:
# [t_name]    a name for this transaction for future referencing, symbol
# [t_type]    numeric code as recognized in vpsAdmin
class Transaction < ActiveRecord::Base
  belongs_to :transaction_chain
  belongs_to :user
  belongs_to :node
  belongs_to :vps
  belongs_to :depends_on, class_name: 'Transaction'
  has_many :transaction_confirmations

  enum done: %i(waiting done staged)
  enum reversible: %i(not_reversible is_reversible keep_going)

  before_save :set_init_values

  validates :queue, inclusion: {
    in: %w(general storage network vps zfs_send mail outage queue)
  }

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
        ::Transaction.register_type(t, self)
      else
        @t_type
      end
    end

    def queue(q=nil)
      if q
        @queue = q
      else
        @queue
      end
    end

    def irreversible
      @reversible = :not_reversible
    end

    def reversible?
      @reversible.nil? ? true : @reversible == :is_reversible
    end

    def keep_going
      @reversible = :keep_going
    end

    def register_type(t, klass)
      @types ||= {}
      @types[t] = klass
    end

    def for_type(t)
      @types[t]
    end
  end

  # Called from TransactionChain when appending transaction.
  # Transaction is to be in +chain+, +dep+ is the id of the previous transaction
  # in the chain.
  # When given a block, it is called in the context of Confirmable.
  #
  # @param chain [TransactionChain]
  # @param dep [Integer] id of transaction to depend on
  # @param opts [Hash] additional options
  # @option opts [Array] args
  # @option opts [Hash] kwargs
  # @option opts [Boolean] urgent
  # @option opts [Integer] prio
  # @option opts [Boolean] retain_context
  # @option opts [Symbol] reversible one of :is_reversible, :not_reversible, :keep_going
  # @option opts [Symbol] queue
  def self.fire_chained(chain, dep, opts, &block)
    t = new

    t.transaction_chain = chain
    t.depends_on_id = dep
    t.handle = t.class.t_type if t.class.t_type
    t.queue = (opts[:queue] || t.class.queue || 'general').to_s
    t.urgent = opts[:urgent]
    t.priority = opts[:prio] || 0

    reversible = opts[:reversible] || @reversible
    t.reversible = reversible.nil? ? :is_reversible : reversible

    if block
      t.done = :staged
      t.save!

      c = Confirmable.new(t)

      if opts[:retain_context]
        block.call(c)

      else
        c.instance_exec(t, &block)
      end
    end

    cmd_input = t.params(
      *  (opts[:args] || []),
      ** (opts[:kwargs] || {}),
    )
    cmd_input ||= {}

    t.input = {
      transaction_chain: t.transaction_chain_id,
      depends_on: t.depends_on_id,
      handle: t.handle,
      node: t.node_id,
      reversible: self.reversibles[t.reversible],
      input: cmd_input,
    }.to_json
    t.signature = VpsAdmin::API::TransactionSigner.sign_base64(t.input)
    t.done = :waiting

    t.save!
    t
  end

  # Set default values for start time, success, done and user id.
  def set_init_values
    self.status = 0
    self.user_id = User.current && User.current.id
  end

  # Must be implemented in subclasses.
  # Returns hash of parameters for single transaction.
  def params(*args, **kwargs)
    raise NotImplementedError
  end

  def name
    self.class.for_type(handle).to_s.demodulize
  end

  # Configure transaction confirmations - objects in the database
  # that are created/edited/destroyed by the transaction.
  # The actions will be confirmed only when the transaction
  # successfully finishes.
  class Confirmable
    def initialize(t)
      @transaction = t
    end

    # Create an object. Pass the object as an argument.
    def create(obj)
      add_confirmable(:create_type, obj)
    end

    # Create an object which does not have attribute +confirmed+.
    def just_create(obj)
      add_confirmable(:just_create_type, obj)
    end

    # Destroy an object. Pass the object as an argument.
    def destroy(obj)
      add_confirmable(:destroy_type, obj)
    end

    # Just destroy the row. The object does not have attribute
    # +confirmed+
    def just_destroy(obj)
      add_confirmable(:just_destroy_type, obj)
    end

    # Confirm already changed attributes.
    # +attrs+ is a hash of original attributes of +obj+.
    # Attributes are first changed in the model and when
    # the transaction succeeds, no action is taken. If
    # it fails, than the original value is restored.
    def edit_before(obj, attrs = nil, **kwattrs)
      add_confirmable(:edit_before_type, obj, attrs, kwattrs)
    end

    # Edit hash of attributes +attrs+ of an object +obj+.
    # The model is updated only after the transaction succeeds.
    def edit_after(obj, attrs = nil, **kwattrs)
      add_confirmable(:edit_after_type, obj, attrs, kwattrs)
    end

    def decrement(obj, attr)
      add_confirmable(:decrement_type, obj, attr)
    end

    def increment(obj, attr)
      add_confirmable(:increment_type, obj, attr)
    end

    alias_method :edit, :edit_after

    protected
    def add_confirmable(type, obj, attrs = nil, kwattrs = nil)
      pk = obj.class.primary_key
      pks = {}

      if pk.is_a?(Array)
        pk.each { |col| pks[col] = obj.send(col) }
      else
        pks[pk] = obj.id
      end

      input_attrs =
        if attrs && kwattrs && kwattrs.any?
          raise ArgumentError, 'provide attrs either as a hash or keyword arguments'
        else
          attrs || kwattrs
        end

      translated_attrs =
        if input_attrs.is_a?(::Hash)
          Hash[input_attrs.map do |k, v|
            if v === true
              [k, 1]
            elsif v === false
              [k, 0]
            else
              [k, v]
            end
          end]
        else
          input_attrs
        end

      ::TransactionConfirmation.create(
        parent_transaction: @transaction,
        class_name: obj.class.name,
        table_name: obj.class.table_name,
        row_pks: pks,
        attr_changes: translated_attrs,
        confirm_type: type
      )
    end
  end
end

module Transactions
  module Vps              ; end
  module Shaper           ; end
  module Firewall         ; end
  module Storage          ; end
  module Utils            ; end
  module Hypervisor       ; end
  module Mail             ; end
  module Network          ; end
  module Maintenanceindow ; end
  module Pool             ; end
  module Queue            ; end
  module UserNamespace    ; end
  module NetworkInterface ; end
  module Export           ; end
end
