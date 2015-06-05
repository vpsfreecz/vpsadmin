module VpsAdmin::API
  # Lifetimes define a set of states which an object can go through.
  # The states are:
  #   - active
  #   - suspended
  #   - soft_delete
  #   - hard_delete
  #   - deleted
  #
  # The default chain of states that an object goes through is:
  # active, soft_delete, hard_delete, deleted
  #
  # An object is created in state +active+ and it then depends on the
  # object how and when it will change states. An expiration can be set.
  # When the expiration date passes, the object goes to the next state
  # in chain.
  #
  # Every model and resource that uses lifetimes must include the following
  # modules:
  # [model] VpsAdmin::API::Lifetimes::Model
  # [resource] VpsAdmin::API::Lifetimes::Resource
  #
  # The model MUST has the following attributes (columns):
  #   - object_state, :integer, null: false
  #   - expiration_date, :datetime, null: true
  #
  # The model then defines what should happen when the object enters
  # or leaves a state. This behaviour is defined in a transaction chain.
  # If the object does not need anything special to happen on state change,
  # the transaction chains don't have to be specified.
  #
  # There are two directions in which the state can change. Downward (enter) -
  # closer to object destruction and upward (leave) - further from destruction.
  #
  #   class User < ActiveRecord::Base
  #     include VpsAdmin::API::Lifetimes::Model
  #     set_object_states suspended: {
  #                           enter: TransactionChains::User::Suspend,
  #                           leave: TransactionChains::User::Resume
  #                       },
  #                       soft_delete: {
  #                          enter: TransactionChains::User::SoftDelete,
  #                           leave: TransactionChains::User::Revive
  #                      }
  #   end
  #
  # When going through multiple states at once, all transaction chains
  # are invoked in the correct order. Assuming that the user is in an +active+
  # state:
  #
  #   user.set_object_state(:soft_delete)
  #
  # it will call the
  # following chains: +suspended[:enter]+, +soft_delete[:enter]+.
  #
  # Return the object to the original state:
  #
  #   user.set_object_state(:active)
  #
  # will call +soft_delete[:leave]+ and +suspended[:leave]+.
  #
  # This module also logs all state changes.
  # The object state should be changed by
  # Lifetimes::Model::InstanceMethods::set_object_state.
  # When changing the +object_state+ attribute directly, needed chains
  # are not invoked and it is not saved to log.
  #
  # Lifetimes::Resource defines an API resource Lifetimes::Resource::StateLog.
  # Object's state change log may be viewed using this resource. It also
  # adds parameters and methods to existing actions, see Lifetimes::Resource
  # for more information.
  #
  # The state should be changed through action +Update+ and action Delete
  # should set the state to +soft_delete+, +hard_delete+
  # or delete it completely. depending on the object behaviour.
  module Lifetimes
    # A list of all possible states objects can be in.
    STATES = %i(active suspended soft_delete hard_delete deleted)

    # Register models that use lifetimes.
    def self.register_model(model)
      @models ||= []
      @models << model
    end

    # Returns registered models.
    def self.models
      @models || []
    end

    # When this module is included in a class derived from HaveAPI::Resource,
    # it defines a resource StateLog, adds parameters to some of the actions
    # and defines helper methods in them.
    #
    # It adds the following parameters:
    #   - Index gets input parameter +object_state+ for filtering and output
    #     parameters +object_state+ and +expiration_date+
    #   - Show gets output parameters +object_state+ and +expiration_date+
    #   - Create gets output parameters +object_state+ and +expiration_date+
    #   - Update gets input parameters +object_state+ and +expiration_date+
    #
    # Action update can use method +update_object_state(object)+. It finds
    # parameters from action's input and attempts to change object state.
    #
    #   class Update < HaveAPI::Actions::Defaults::Update
    #       ...
    #       def exec
    #         obj = MyObject.find(params[:my_object_id])
    #         update_object_state(obj) if input[:object_state]
    #       end
    #   end
    #
    # +update_object_state!()+ will end the request with an error
    # if the input contains additional parameters not used by the method.
    # It will also return immediately after the state has been changed
    # by calling HaveAPI::Action.ok().
    module Resource
      def self.included(r)
        # Create a resource for browsing object state log
        parent_object_id = "#{r.to_s.demodulize.underscore}_id"

        log = r.define_resource(:StateLog) do
          route ":#{parent_object_id}/state_logs"
          version r.version
          desc 'Browse object\'s state log'
          model ::ObjectState
        end

        params = Proc.new do
          id :id
          string :state
          datetime :changed_at, db_name: :created_at
          datetime :expiration, db_name: :expiration_date
          resource VpsAdmin::API::Resources::User, value_label: :login
          string :reason
        end

        log.define_action(:Index, superclass: HaveAPI::Actions::Default::Index) do
          const_set(:PARENT_RESOURCE, r)
          const_set(:PARENT_OBJECT_ID, parent_object_id.to_sym)

          desc 'List object state changes'

          output(:object_list, &params)

          authorize do |u|
            allow if u.role == :admin
          end

          def query
            ::ObjectState.where(
                class_name: self.class::PARENT_RESOURCE.model.name,
                row_id: params[self.class::PARENT_OBJECT_ID]
            )
          end

          def count
            query.count
          end

          def exec
            query.limit(input[:limit]).offset(input[:offset]).order('created_at')
          end
        end

        # Add parameters to existing actions
        log.define_action(:Show, superclass: HaveAPI::Actions::Default::Show) do
          const_set(:PARENT_RESOURCE, r)
          const_set(:PARENT_OBJECT_ID, parent_object_id.to_sym)

          desc 'Show object state change'

          output(&params)

          authorize do |u|
            allow if u.role == :admin
          end

          def prepare
            @state = ::ObjectState.where(
                class_name: self.class::PARENT_RESOURCE.model.name,
                row_id: params[self.class::PARENT_OBJECT_ID],
                id: params[:state_log_id]
            ).take!
          end

          def exec
            @state
          end
        end

        r.params(:lifetime_state) do
          string :object_state, label: 'Object state',
                 choices: Private.states(r.model)
        end

        r.params(:lifetime_expiration) do
          use :lifetime_state
          datetime :expiration_date, label: 'Expiration',
              desc: 'A date after which the state will progress'
        end

        r.params(:lifetime_all) do
          use :lifetime_expiration
          string :change_reason, label: 'Reason',
                 desc: 'Reason for the state change. May be mailed to the user.'
        end

        if r.const_defined?(:Index)
          r::Index.input do
            use :lifetime_state
          end

          r::Index.output do
            use :lifetime_expiration
          end
        end

        if r.const_defined?(:Show)
          r::Show.output do
            use :lifetime_expiration
          end
        end

        if r.const_defined?(:Create)
          r::Create.output do
            use :lifetime_expiration
          end
        end

        if r.const_defined?(:Update)
          r::Update.input do
            use :lifetime_all
          end

          Private.action_methods(r::Update)
        end

        if r.const_defined?(:Delete)
          r::Delete.input do
            states = Private.states(r.model) & %i(soft_delete hard_delete deleted)

            use :lifetime_all
            patch :object_state,
                  choices: states,
                  default: states.first,
                  fill: true
          end

          Private.action_methods(r::Delete)
        end
      end
    end

    # Module for inclusion in models. Defines an enum +object_states+
    # and adds helper class and instance methods.
    module Model
      module ClassMethods
        # This methods needs to be called even if without any arguments.
        # The argument is a hash in form of
        # <state> => {[enter => <chain>], [leave => <chain>]}
        # It can also contain key +states+, which must be an array
        # containing a subset of states the object can be in. This is used
        # if the object does not use all the states defined in Lifetimes::STATES.
        def set_object_states(states = {})
          @states ||= Lifetimes::STATES
          @state_changes ||= {}

          states.each do |k, v|
            if k == :states
              @states = v

            else
              @state_changes[k] = v
            end
          end

          @state_changes.each_key do |k|
            unless @states.include?(k)
              fail "invalid state '#{k}' for #{self.to_s}"
            end
          end
        end
      end

      module InstanceMethods
        # Change object's state. Invokes the chains configured with
        # ClassMethods.set_object_states. If +chain+ is provided, all the chains
        # are embedded in it.
        def set_object_state(state, reason: nil, user: nil, expiration: nil, chain: nil)
          unless Private.states(self.class).include?(state)
            fail "#{self.class.to_s} does not have state '#{state}'"
          end

          Private.change_state(self, state, chain, reason || '', user || ::User.current, expiration)
        end

        # Move the object to next state (up or down - direction leave or enter).
        # Accepts the same keyword arguments as #set_object_state.
        def progress_object_state(direction = :enter, *args)
          states = Private.states(self.class)
          i = states.index(object_state.to_sym)
          target = states[ direction == :enter ? i + 1 : i - 1 ]

          if target
            set_object_state(target, *args)

          else
            fail "cannot progress state in chosen direction (#{direction})"
          end
        end

        # Keep the same state and just set new expiration date.
        def set_expiration(expiration, save: true, user: nil, reason: nil)
          self.expiration_date = expiration

          log = ::ObjectState.create!(
              class_name: self.class.name,
              row_id: self.id,
              state: self.object_state,
              expiration_date: expiration,
              reason: reason,
              user: user || ::User.current
          )

          save! if save
          log
        end

        # Returns the current (last) state.
        def current_state
          ::ObjectState.where(
              class_name: self.class.name,
              row_id: self.id
          ).order('created_at DESC').take
        end
      end

      def self.included(model)
        return if Lifetimes.models.include?(model)

        model.send(:extend, ClassMethods)
        model.send(:include, InstanceMethods)

        model.enum object_state: Lifetimes::STATES
        model.before_create(Private::ModelCallback.new)
        model.after_create(Private::ModelCallback.new)

        Lifetimes.register_model(model)
      end
    end

    module Private
      def self.states(o)
        o.instance_variable_get('@states')
      end

      def self.state_changes(o)
        o.instance_variable_get('@state_changes')
      end

      def self.change_state(obj, target, chain, reason, user, expiration)
        states = states(obj.class)
        t_i = states.index(target)
        o_i = states.index(obj.object_state.to_sym)
        enter = t_i > o_i
        state_chain = enter ? states[o_i+1..t_i] : states[t_i+1..o_i].reverse

        if !enter && o_i >= (states.index(:hard_delete) || states.index(:deleted))
          raise Exceptions::CannotLeaveState,
                "cannot leave state '#{obj.object_state}'"
        end

        log = ::ObjectState.new_log(obj, target, reason, user, expiration)

        chain_args = [obj, target, state_chain, enter, state_changes(obj.class), log]

        if chain
          chain.use_chain(TransactionChains::Lifetimes::Wrapper, args: chain_args)

        else
          TransactionChains::Lifetimes::Wrapper.fire(*chain_args)
        end
      end

      def self.action_methods(action)
        action.send(:define_method, :change_object_state?) do
          input[:object_state] || input[:expiration_date]
        end

        action.send(:define_method, :update_object_state) do |obj|
          unless (input.keys - %i(object_state change_reason expiration_date)).empty?
            raise VpsAdmin::API::Exceptions::TooManyParameters,
                  'cannot update any parameters when changing object state'
          end

          if !input[:object_state] || obj.object_state == input[:object_state]
            if input[:expiration_date]
              obj.set_expiration(
                  input[:expiration_date],
                  reason: input[:change_reason]
              )

            else
              error("object_state already is '#{obj.object_state}'")
            end

          else
            obj.set_object_state(
                input[:object_state].to_sym,
                reason: input[:change_reason],
                expiration: input[:expiration_date]
            )
          end

          obj
        end

        action.send(:define_method, :update_object_state!) do |obj|
          begin
            ok(update_object_state(obj))

          rescue VpsAdmin::API::Exceptions::TooManyParameters => e
            error(e.message)
          end
        end
      end

      class ModelCallback
        def before_create(record)
          record.object_state ||= Private.states(record.class).first
        end

        def after_create(record)
          s = ::ObjectState.new(
              class_name: record.class.name,
              row_id: record.id,
              state: record.object_state,
              expiration_date: record.expiration_date,
              reason: 'Object was created.',
              user: ::User.current
          )
          s.save!
        end
      end
    end
  end
end
