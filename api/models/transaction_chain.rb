require 'vpsadmin/api/hash_options'

# Transaction chain is a container for multiple transactions.
# Every transaction chain inherits this class. Chains must implement
# method TransactionChain#link_chain.
# All transaction must be in a chain. Transaction without a chain does not
# have a meaning.
class TransactionChain < ApplicationRecord
  INFER_RESOURCE_EVENT_RELATION = Object.new.freeze

  CONCERN_CLASS_LABELS = {
    'Branch' => 'Dataset branch',
    'ChangeRequest' => 'Request',
    'Dataset' => 'Dataset',
    'DatasetExpansion' => 'Dataset expansion',
    'DatasetInPool' => 'Dataset in pool',
    'DnsResolver' => 'DNS resolver',
    'DnsServerZone' => 'Server zone',
    'DnsZone' => 'DNS zone',
    'DnsZoneTransfer' => 'Zone transfer',
    'Export' => 'Export',
    'HostIpAddress' => 'Host IP',
    'IncidentReport' => 'Incident report',
    'MigrationPlan' => 'Migration',
    'Mount' => 'Mount',
    'NetworkInterface' => 'Interface',
    'Node' => 'Node',
    'Outage' => 'Outage',
    'Pool' => 'Pool',
    'RegistrationRequest' => 'Registration',
    'SecurityAdvisory' => 'Security',
    'Snapshot' => 'Snapshot',
    'SnapshotDownload' => 'Snapshot download',
    'SnapshotInPool' => 'Snapshot in pool',
    'User' => 'User',
    'UserPayment' => 'Payment',
    'Vps' => 'VPS'
  }.freeze

  LABEL_OPTIONAL_CLASSES = %w[
    TransactionChains::Lifetimes::NotImplemented
    TransactionChains::NetworkInterface::Veth::Base
    TransactionChains::SnapshotInPool::FreeClone
    TransactionChains::SnapshotInPool::UseClone
    TransactionChains::Vps::Migrate::Base
  ].freeze

  has_many :transactions
  has_many :transaction_chain_concerns, dependent: :delete_all
  belongs_to :user
  belongs_to :user_session

  enum :state, %i[staged queued done rollbacking failed fatal resolved]
  enum :concern_type, %i[chain_affect chain_transform]

  attr_reader :acquired_locks
  attr_accessor :last_id, :last_node_id, :dst_chain, :named, :global_locks,
                :locks, :urgent, :prio, :reversible, :deferred_result_events

  include HaveAPI::Hookable
  include VpsAdmin::API::HashOptions

  # Create new transaction chain. This method has to be used, do not
  # create instances of TransactionChain yourself.
  # All arguments are passed to TransactionChain#link_chain.
  def self.fire(*args, **kwargs)
    fire2(args:, kwargs:)
  end

  # Same as TransactionChain.fire, except that arguments are passed
  # as a hash option +args+. This allows to also pass a list of global locks.
  # @param args [Array]
  # @param kwargs [Hash]
  # @param locks [Array] list of global locks
  def self.fire2(args: [], kwargs: {}, locks: [])
    unless VpsAdmin::API::TransactionSigner.can_sign?
      raise VpsAdmin::API::Exceptions::ConfigurationError,
            'Transaction signing not enabled, please contact support if this error persists'
    end

    ret = nil
    chain = nil
    started_event = nil

    TransactionChain.transaction(requires_new: true) do
      chain = new
      chain.name = chain_name
      chain.state = :staged
      chain.size = 0
      chain.user = ::User.current
      chain.user_session = ::UserSession.current
      chain.urgent_rollback = urgent_rollback? || false
      chain.save
      started_event = VpsAdmin::API::Events::OperationLifecycle.prepare_started!(chain)

      chain.global_locks = locks

      # link_chain will raise ResourceLocked if it is unable to acquire
      # a lock. It will cause the transaction to be rolled back
      # and the exception will be propagated.
      ret = chain.link_chain(*args, **kwargs)
      VpsAdmin::API::Events::ActionPolicies.defer_transaction_chain_resources!(
        chain
      )

      if chain.empty?
        raise 'empty' unless chain.class.allow_empty?

        VpsAdmin::API::Events::OperationLifecycle.emit_deferred_immediately!(chain)
        chain.release_locks
        started_event.destroy!
        chain.destroy!
        chain = nil
        started_event = nil
        next

      end

      chain.capture_event_owner_concern!
      chain.append_deferred_result_events!
      chain.state = :queued
      chain.save!
      VpsAdmin::API::Events::OperationLifecycle.finalize_started!(started_event, chain)
    end

    if chain
      route_started_event(started_event)
      emit_state_changed_event(chain, previous_state: 'staged', state: 'queued')
    end

    [chain, ret]
  end

  def self.emit_state_changed_event(chain, previous_state:, state:)
    VpsAdmin::API::Events.emit_transaction_chain_state!(
      chain,
      previous_state:,
      state:
    )
  rescue StandardError => e
    warn "Unable to emit transaction chain event for chain ##{chain.id}: #{e.class}: #{e.message}"
  end

  def self.route_started_event(event)
    VpsAdmin::API::Events::OperationLifecycle.route_started!(event)
  rescue StandardError => e
    warn "Unable to route operation start event ##{event.id}: #{e.class}: #{e.message}"
  end

  # The chain name is a class name in lowercase with added
  # underscores.
  def self.chain_name
    to_s.demodulize.underscore
  end

  # Include this chain in +chain+. All remaining arguments are passed
  # to #link_chain.
  # Method #link_chain is called in the same way as in ::fire,
  # except that all transactions are appended to +chain+,
  # not to instance of self.
  # This method should not be called directly, but via #use_chain.
  #
  # @param chain
  # @param opts [Hash]
  # @option opts [Array] args ([])
  # @option opts [Hash] kwargs ({})
  # @option opts [Boolean] urgent (false)
  # @option opts [Integer] prio (0)
  # @option opts [Symbol] reversible one of :is_reversible, :not_reversible, :keep_going
  # @option opts [Symbol] method (:link_chain)
  # @option opts [Hash] hooks ({})
  def self.use_in(chain, opts = {})
    opts[:args] ||= []
    opts[:kwargs] ||= {}
    opts[:urgent] = false if opts[:urgent].nil?
    opts[:prio] ||= 0
    opts[:method] ||= :link_chain
    opts[:hooks] ||= {}

    c = new

    c.last_id = chain.last_id
    c.last_node_id = chain.last_node_id
    c.dst_chain = chain.dst_chain
    c.named = chain.named
    c.global_locks = chain.global_locks
    c.locks = chain.locks
    c.urgent = opts[:urgent]
    c.prio = opts[:prio]
    c.reversible = opts[:reversible]

    opts[:hooks].each do |k, v|
      c.connect_hook(k, &v)
    end

    ret = c.send(opts[:method], *opts[:args], **opts[:kwargs])

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

  def self.localized_label(default: nil)
    label_default = label || default || chain_name.humanize

    VpsAdmin::API::I18n.t(label_i18n_key, default: label_default)
  end

  def self.label_i18n_key
    "transaction_chains.labels.#{transaction_chain_i18n_path(name)}"
  end

  # Override the stable, public operation name emitted for this chain.
  def self.event_operation(value = nil)
    if value
      @event_operation = value.to_s
    elsif instance_variable_defined?(:@event_operation)
      @event_operation
    elsif superclass.respond_to?(:event_operation)
      superclass.event_operation
    end
  end

  def self.transaction_chain_label_defaults
    descendants.each_with_object({}) do |klass, ret|
      next if klass.name.nil? || klass.label.nil?

      ret[klass.label_i18n_key] = klass.label
    end
  end

  def self.transaction_chain_label_errors
    descendants.filter_map do |klass|
      next if klass.name.nil? || klass.label || LABEL_OPTIONAL_CLASSES.include?(klass.name)

      "#{klass.name}: missing label"
    end
  end

  def self.concern_class_label_defaults
    CONCERN_CLASS_LABELS.to_h do |klass, label|
      [concern_class_i18n_key(klass), label]
    end
  end

  def self.concern_class_i18n_key(klass)
    "transaction_chains.concerns.classes.#{klass.to_s.underscore}"
  end

  def self.concern_class_label(klass)
    klass = klass.to_s
    label_default = CONCERN_CLASS_LABELS.fetch(klass, klass)

    VpsAdmin::API::I18n.t(concern_class_i18n_key(klass), default: label_default)
  end

  def self.transaction_chain_i18n_path(class_name)
    parts = class_name.to_s.split('::')
    index = parts.rindex('TransactionChains')
    return parts.map(&:underscore).join('.') unless index

    suffix = parts[(index + 1)..]
    prefix = parts[0...index]

    if prefix[0, 3] == %w[VpsAdmin API Plugins] && prefix[3]
      (['plugins', prefix[3].underscore] + suffix.map(&:underscore)).join('.')
    else
      suffix.map(&:underscore).join('.')
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

  def initialize(*_, **_)
    super

    @locks = []
    @named = {}
    @dst_chain = self
    @urgent = false
    @prio = 0
    @deferred_result_events = []
  end

  # All chains must implement this method.
  def link_chain(*args, **kwargs)
    raise NotImplementedError
  end

  # Helper method for acquiring resource locks. TransactionChain remembers
  # what locks it has, therefore it is safe to lock one resource more than
  # once, which happens when including other chains with ::use_in.
  def lock(obj, *, **)
    return if @global_locks.detect { |l| l.locks?(obj) }
    return if @locks.detect { |l| l.locks?(obj) }

    lock = obj.acquire_lock(@dst_chain, *, **)
    @locks << lock
    lock
  end

  # Release all locks acquired by this and all nested chains.
  def release_locks
    @locks.each(&:release)
  end

  # Append transaction of +klass+ with +opts+ to the end of the chain.
  # If +name+ is set, it is used as an anchor which other
  # transaction in chain might hang onto.
  # +args+ and +block+ are forwarded to target transaction.
  # Use the block to configure transaction confirmations, see
  # Transaction::Confirmable.
  # Deprecated in favor of #append_t.
  #
  # @param klass [Transaction] transaction subclass
  # @param opts [hash] options
  # @option opts [Array] args
  # @option opts [Hash] kwargs
  # @option opts [Boolean] urgent
  # @option opts [Integer] prio
  # @option opts [Symbol] name
  # @option opts [Symbol] reversible one of :is_reversible, :not_reversible, :keep_going
  # @option opts [Symbol] queue
  def append(klass, opts = {}, &block)
    do_append(@last_id, klass, opts, block)
  end

  # This method will be deprecated in the near future.
  # Append transaction of +klass+ with +opts+ to previosly created anchor
  # +dep_name+ instead of the end of the chain.
  # If +name+ is set, it is used as an anchor which other
  # transaction in chain might hang onto.
  # +args+ and +block+ are forwarded to target transaction.
  #
  # @param dep_name [Symbol] name of transaction to depend on
  # @param klass [Transaction] transaction subclass
  # @param opts [hash] options
  # @option opts [Array] args
  # @option opts [Hash] kwargs
  # @option opts [Boolean] urgent
  # @option opts [Integer] prio
  # @option opts [Symbol] name
  # @option opts [Symbol] reversible one of :is_reversible, :not_reversible, :keep_going
  # @option opts [Symbol] queue
  # @see TransactionChain#append_t
  def append_to(dep_name, klass, opts = {}, &block)
    do_append(@named[dep_name], klass, opts, block)
  end

  # Will replace #append in the future. #append_t does not execute the block
  # in Confirmable instance context, but uses the original context in which
  # the block was defined - +self+ does not change meaning.
  #
  # @param klass [Transaction] transaction subclass
  # @param opts [hash] options
  # @option opts [Array] args
  # @option opts [Hash] kwargs
  # @option opts [Boolean] urgent
  # @option opts [Integer] prio
  # @option opts [Symbol] name
  # @option opts [Symbol] reversible one of :is_reversible, :not_reversible, :keep_going
  # @option opts [Symbol] queue
  def append_t(klass, opts = {}, &block)
    do_append(@last_id, klass, opts, block, true)
  end

  # Append a transaction or add is as a NoOp
  #
  # If option `noop` is set to true, the transaction is added as
  # {Transactions::Utils::NoOp}. The confirmation block is executed as is.
  #
  # @param klass [Transaction] transaction subclass
  # @param opts [hash] options
  # @option iots [Boolean] noop
  # @option opts [Array] args
  # @option opts [Hash] kwargs
  # @option opts [Boolean] urgent
  # @option opts [Integer] prio
  # @option opts [Symbol] name
  # @option opts [Symbol] reversible one of :is_reversible, :not_reversible, :keep_going
  # @option opts [Symbol] queue
  def append_or_noop_t(klass, opts = {}, &block)
    noop = opts.delete(:noop)

    if noop
      klass = Transactions::Utils::NoOp
      opts[:args] = [find_node_id]
      opts[:kwargs] = {}
    end

    do_append(@last_id, klass, opts, block, true)
  end

  # Call this method from TransactionChain#link_chain to include
  # +chain+. +args+ are passed to the chain as in ::fire.
  #
  # @param chain
  # @param opts [Hash]
  # @option opts [Array] args
  # @option opts [Hash] kwargs
  # @option opts [Boolean] urgent
  # @option opts [Integer] prio
  # @option opts [Symbol] reversible one of :is_reversible, :not_reversible, :keep_going
  # @option opts [Symbol] method
  # @option opts [Hash] hooks
  def use_chain(chain, opts = {})
    args = opts[:args] || []
    kwargs = opts[:kwargs] || {}
    urgent = opts[:urgent].nil? ? self.urgent : opts[:urgent]
    prio = opts[:prio] || self.prio

    c, ret = chain.use_in(self, {
                            args: args.is_a?(Array) ? args : [args],
                            kwargs:,
                            urgent:,
                            prio:,
                            reversible: opts[:reversible],
                            method: opts[:method],
                            hooks: opts[:hooks]
                          })
    @last_id = c.last_id
    @last_node_id = c.last_node_id
    ret
  end

  def mail(name, _opts = {})
    raise NotImplementedError,
          "TransactionChain#mail(#{name.inspect}) was replaced by event routing"
  end

  def mail_custom(_opts)
    raise NotImplementedError,
          'TransactionChain#mail_custom was replaced by event routing'
  end

  def route_event!(event_type, **)
    event = prepare_event!(event_type, **)
    release_event_deliveries!(event)
    event
  end

  def prepare_event!(event_type, payload: nil, **)
    VpsAdmin::API::Events.emit!(
      event_type,
      **,
      payload:,
      payload_additions: operation_event_payload,
      release: false
    )
  end

  # Store a completion event in the signed input of a final no-op transaction.
  # The supervisor materializes it only after the whole chain reaches +done+.
  def defer_result_event!(event_type, user: nil, vps: nil, source: nil,
                          source_class: nil, source_id: nil, subject: nil,
                          summary: nil, payload: nil, severity: nil,
                          category: nil, ip_addr: nil, vpses: nil)
    target = current_chain
    target.deferred_result_events ||= []
    target.deferred_result_events << {
      event_type: event_type.to_s,
      user_id: record_id(user),
      vps_id: record_id(vps),
      source_class: source_class || source&.class&.name,
      source_id: source_id || record_id(source),
      subject:,
      summary:,
      payload: (payload || {}).dup,
      severity: severity&.to_s,
      category: category&.to_s,
      ip_addr:,
      vps_ids: vpses&.map { |item| record_id(item) }
    }.compact.deep_stringify_keys
  end

  def defer_resource_event!(action, object, changed_fields: [],
                            owner: INFER_RESOURCE_EVENT_RELATION,
                            vps: INFER_RESOURCE_EVENT_RELATION)
    operations = VpsAdmin::API::Events::ResourceOperations
    action = action.to_s
    unless operations::ACTIONS.include?(action)
      raise ArgumentError, "unsupported resource event action #{action.inspect}"
    end

    related_vps = if vps.equal?(INFER_RESOURCE_EVENT_RELATION)
                    operations.related_vps(object)
                  else
                    vps
                  end
    resource_owner = if owner.equal?(INFER_RESOURCE_EVENT_RELATION)
                       operations.resource_owner(object, vps: related_vps)
                     else
                       owner
                     end
    actor = ::User.current
    session = ::UserSession.current
    resource_type = object.class.base_class.name
    resource_id = object.id
    fields = Array(changed_fields).map(&:to_s).uniq -
             operations::IGNORED_CHANGED_FIELDS

    defer_result_event!(
      "resource.#{action}",
      user: resource_owner,
      vps: related_vps,
      source_class: resource_type,
      source_id: resource_id,
      subject: "#{resource_type} ##{resource_id} #{action}",
      summary: operations.resource_summary(
        action,
        resource_type,
        resource_id,
        actor:
      ),
      payload: {
        resource_type:,
        resource_id:,
        action:,
        actor_user_id: actor&.id,
        actor_user_login: actor&.login,
        admin_user_id: session&.admin_id,
        user_session_id: session&.id,
        changed_fields: fields.sort
      }.compact,
      ip_addr: session&.client_ip_addr || session&.api_ip_addr
    )
  end

  def append_deferred_result_events!
    return if deferred_result_events.blank?

    append_t(
      Transactions::Utils::NoOp,
      args: [find_node_id],
      kwargs: { result_events: deferred_result_events }
    )
  end

  def release_event_deliveries!(event)
    return if event.nil?

    ids = event.event_deliveries.where(state: 'prepared').order(:id).pluck(:id)
    return if ids.empty?

    transaction_id = append_t(Transactions::EventDelivery::Notify, args: [find_node_id, ids])
    event.event_deliveries.where(id: ids, state: 'prepared').update_all(
      transaction_id:,
      updated_at: Time.now
    )
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

  # Preserve the affected account as part of the successfully built chain.
  # Concerned objects can be deleted while the chain is running, but the owner
  # concern remains available when node state changes are projected to Events.
  def capture_event_owner_concern!
    owner = VpsAdmin::API::Events::OperationLifecycle.owner_from_live_concerns(self)
    return unless owner

    last_concern = transaction_chain_concerns.order(:id).last
    return if last_concern&.class_name == ::User.name && last_concern.row_id == owner.id

    TransactionChainConcern.create!(
      transaction_chain: self,
      class_name: ::User.name,
      row_id: owner.id
    )
  end

  def format_concerns
    ret = { type: concern_type[6..], objects: [], labels: {} }

    transaction_chain_concerns.each do |c|
      ret[:objects] << [c.class_name, c.row_id]
      ret[:labels][c.class_name] = self.class.concern_class_label(c.class_name)
    end

    ret
  end

  # Returns true if the chain is being used (included) by another chain
  # using method self.use_chain.
  def included?
    @dst_chain != self
  end

  # @return [TransactionChain]
  def current_chain
    id ? self : dst_chain
  end

  def empty?
    size == 0
  end

  def label
    Kernel.const_get(type).localized_label(default: name)
  rescue NameError
    name || type
  end

  # Return the node ID of last transaction. Find first available server if no
  # transactions have been appended yet.
  def find_node_id
    @last_node_id || @last_node_id = ::Node.first_available_transaction_runner.id
  end

  protected

  def operation_event_payload
    chain = current_chain
    return {} unless chain&.id

    { operation_id: chain.id }
  end

  def record_id(record)
    record.respond_to?(:id) ? record.id : record
  end

  private

  # @param dep
  # @param klass
  # @param opts [Hash]
  # @option opts [Array] args
  # @option opts [Hash] kwargs
  # @option opts [Boolean] urgent
  # @option opts [Integer] prio
  # @option opts [Symbol] name
  # @option opts [Symbol] reversible one of :is_reversible, :not_reversible, :keep_going
  # @option opts [Symbol] queue
  # @param retain_context [Boolean]
  def do_append(dep, klass, opts, block, retain_context = false)
    t_opts = {
      args: opts[:args] && (opts[:args].is_a?(Array) ? opts[:args] : [opts[:args]]),
      kwargs: opts[:kwargs],
      urgent: opts[:urgent].nil? ? urgent : opts[:urgent],
      prio: opts[:prio] || prio,
      reversible: opts[:reversible] || reversible,
      queue: opts[:queue],
      retain_context:
    }

    @dst_chain.size += 1
    t = klass.fire_chained(@dst_chain, dep, t_opts, &block)
    @last_node_id = t.node_id
    @last_id = t.id
    @named[opts[:name]] = @last_id if opts[:name]
    @last_id
  end
end

module TransactionChains
  module Cluster; end
  module Node; end
  module Vps; end
  module Ip; end
  module Pool; end
  module Dataset; end
  module DatasetInPool; end
  module Snapshot; end
  module SnapshotInPool; end
  module DatasetTree; end
  module Branch; end
  module User; end
  module Lifetimes; end
  module DnsResolver; end
  module DnsZone; end
  module DnsServerZone; end
  module DnsZoneTransfer; end
  module Mail; end
  module MigrationPlan; end
  module Maintenance; end
  module Network; end
  module UserNamespace; end
  module UserNamespaceMap; end
  module EventDelivery; end

  module NetworkInterface
    module Venet; end
    module Veth; end
    module VethRouted; end
  end

  module Export; end
  module IncidentReport; end
  module HostIpAddress; end
end
