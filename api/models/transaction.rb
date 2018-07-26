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

    t.input = (t.params(* (opts[:args] || [])) || {}).to_json
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
  def params(*args)
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
    def create(*args)
      add_confirmable(:create_type, *args)
    end

    # Create an object which does not have attribute +confirmed+.
    def just_create(*args)
      add_confirmable(:just_create_type, *args)
    end

    # Destroy an object. Pass the object as an argument.
    def destroy(*args)
      add_confirmable(:destroy_type, *args)
    end

    # Just destroy the row. The object does not have attribute
    # +confirmed+
    def just_destroy(*args)
      add_confirmable(:just_destroy_type, *args)
    end

    # Confirm already changed attributes.
    # +attrs+ is a hash of original attributes of +obj+.
    # Attributes are first changed in the model and when
    # the transaction succeeds, no action is taken. If
    # it fails, than the original value is restored.
    def edit_before(obj, attrs)
      add_confirmable(:edit_before_type, obj, attrs)
    end

    # Edit hash of attributes +attrs+ of an object +obj+.
    # The model is updated only after the transaction succeeds.
    def edit_after(obj, attrs)
      add_confirmable(:edit_after_type, obj, attrs)
    end

    def decrement(obj, attr)
      add_confirmable(:decrement_type, obj, attr)
    end

    def increment(obj, attr)
      add_confirmable(:increment_type, obj, attr)
    end

    alias_method :edit, :edit_after

    protected
    def add_confirmable(type, obj, attrs = nil)
      pk = obj.class.primary_key
      pks = {}

      if pk.is_a?(Array)
        pk.each { |col| pks[col] = obj.send(col) }

      else
        pks[pk] = obj.id
      end

      tr_attrs = nil

      if attrs && attrs.is_a?(::Hash)
        tr_attrs = {}

        attrs.each do |k, v|
          if v === true
            tr_attrs[k] = 1

          elsif v === false
            tr_attrs[k] = 0

          else
            tr_attrs[k] = v
          end
        end

      else
        tr_attrs = attrs
      end

      ::TransactionConfirmation.create(
        parent_transaction: @transaction,
        class_name: obj.class.name,
        table_name: obj.class.table_name,
        row_pks: pks,
        attr_changes: tr_attrs,
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
  module OutageWindow     ; end
  module Queue            ; end
  module UserNamespace    ; end
  module NetworkInterface ; end
end
