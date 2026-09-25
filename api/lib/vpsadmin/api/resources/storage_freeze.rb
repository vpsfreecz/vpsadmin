require 'securerandom'

module VpsAdmin::API::Resources
  class StorageFreeze < HaveAPI::Resource
    singular true
    desc 'Storage write admission and database drain status'

    module Access
      def self.allowed?(user)
        session = ::UserSession.current
        user && user.role == :admin &&
          user.object_state == 'active' &&
          user.authentication_allowed_by_lifecycle? &&
          session && session.user_id == user.id &&
          session.admin_id.nil? && session.closed_at.nil?
      end

      def status
        snapshot = ::StorageFreezeStatus.snapshot
        control = ::StorageFreezeControl.singleton!
        matching = control.epoch == snapshot.fetch(:epoch)
        transition = ::StorageFreezeTransition.find_by(new_epoch: snapshot.fetch(:epoch))
        snapshot[:stable_epoch] = false unless matching
        snapshot[:db_drained] = false unless matching

        snapshot.merge(
          reason: matching ? control.reason : nil,
          requested_at: matching ? control.requested_at : nil,
          requested_by_user_id: matching ? control.requested_by_user_id : nil,
          transition: transition && {
            prior_mode: transition.prior_mode,
            new_mode: transition.new_mode,
            prior_epoch: transition.prior_epoch,
            new_epoch: transition.new_epoch,
            actor_user_id: transition.actor_user_id,
            actor_user_session_id: transition.actor_user_session_id,
            actor_user_login: transition.actor_user_login,
            reason: transition.reason,
            created_at: transition.created_at
          },
          observed_at: Time.current
        )
      end

      def change_mode(read_only:)
        ::StorageMutationAdmission.set_read_only_for_user!(
          read_only:, expected_epoch: input[:expected_epoch],
          reason: input[:reason], user: current_user,
          user_session: ::UserSession.current
        )
        status
      rescue ::StorageMutationAdmission::StaleEpoch, ::StorageMutationAdmission::SameMode
        error!(VpsAdmin::API::I18n.message('errors.storage_freeze_conflict'), {}, http_status: 409)
      rescue ArgumentError
        error!(VpsAdmin::API::I18n.message('errors.storage_freeze_invalid_request'), {}, http_status: 422)
      rescue ::StorageMutationAdmission::AuthorizationRefused
        error!(VpsAdmin::API::I18n.message('errors.access_denied'), {}, http_status: 403)
      end
    end

    params(:status) do
      string :mode
      integer :epoch, label: 'Storage mode epoch'
      bool :stable_epoch, label: 'Epoch stable during status scan'
      custom :counts, label: 'Drain counts'
      custom :count_capped, label: 'Counts at the reporting limit'
      custom :sample_chain_ids, label: 'Sample active chain IDs'
      custom :sample_fatal_chain_ids, label: 'Sample fatal chain IDs'
      custom :sample_intent_ids, label: 'Sample blocking intent IDs'
      bool :db_drained, label: 'Database drained',
                        desc: 'Database work has drained; this does not prove node quiescence'
      bool :repair_ready, label: 'Repair ready'
      string :reason, nullable: true
      integer :requested_by_user_id, nullable: true, label: 'Requesting user ID'
      datetime :requested_at, nullable: true, label: 'Mode requested at'
      custom :transition, nullable: true
      datetime :observed_at
    end

    params(:change) do
      integer :expected_epoch, required: true, number: { min: 0 },
                               label: 'Expected storage mode epoch',
                               desc: 'Epoch returned by show; the request fails if it has changed'
      text :reason, required: true, desc: 'Reason for the storage mode change'
    end

    class Show < HaveAPI::Actions::Default::Show
      include Access

      output { use :status }
      authorize { |user| allow if Access.allowed?(user) }

      def exec
        status
      end
    end

    class ReadOnly < HaveAPI::Action
      include Access

      route 'read_only'
      http_method :post
      input { use :change }
      output { use :status }
      authorize { |user| allow if Access.allowed?(user) }

      def exec
        change_mode(read_only: true)
      end
    end

    class ReadWrite < HaveAPI::Action
      include Access

      route 'read_write'
      http_method :post
      input { use :change }
      output { use :status }
      authorize { |user| allow if Access.allowed?(user) }

      def exec
        change_mode(read_only: false)
      end
    end

    class SettleObserver < HaveAPI::Action
      route 'settle_observer'
      http_method :post
      input do
        text :reason, required: true, desc: 'Reason for settling observer intents'
        integer :expected_epoch, required: true, number: { min: 0 },
                                 label: 'Expected storage mode epoch',
                                 desc: 'Frozen epoch returned by show; the request fails if it has changed'
        integer :after_chain_id, default: 0, fill: true, number: { min: 0 },
                                 label: 'Continue after chain ID',
                                 desc: 'Last chain ID from the previous page; use 0 for the first page'
        integer :limit, default: 100, fill: true, number: { min: 1, max: 100 },
                        desc: 'Maximum number of items to examine in one page'
      end
      output do
        string :audit_request_id, label: 'Catch-up audit request ID'
        integer :scanned_chains, label: 'Examined chains'
        integer :settled_intents, label: 'Settled, unverified intents'
        custom :settled_chain_ids, label: 'Settled chain IDs'
        integer :blocked_chains, label: 'Blocked chains'
        custom :blocked_chain_ids, label: 'Blocked chain IDs'
        custom :blocked_reasons, label: 'Reasons chains are blocked'
        integer :after_chain_id, label: 'Continue after chain ID'
        integer :next_after_chain_id, nullable: true, label: 'Next chain cursor'
        bool :has_more, label: 'More chains available'
        integer :limit
      end
      authorize { |user| allow if Access.allowed?(user) }

      def exec
        reason = input[:reason]
        if reason.to_s.strip.empty? || reason.length > 255 || reason.match?(/[[:cntrl:]]/)
          error!(VpsAdmin::API::I18n.message('errors.storage_freeze_invalid_request'), {}, http_status: 422)
        end

        audit = ::StorageMutationAdmission.request_catch_up_for_user!(
          user: current_user, user_session: ::UserSession.current,
          expected_epoch: input[:expected_epoch], reason:,
          after_chain_id: input[:after_chain_id], limit: input[:limit]
        )
        result = ::StorageObserverSettlement.catch_up!(
          limit: input[:limit], after_chain_id: input[:after_chain_id],
          expected_epoch: audit.freeze_epoch
        )
        ::StorageObserverCatchUpAudit.record_completion!(audit, result)
        result.merge(audit_request_id: audit.request_id)
      rescue ::StorageMutationAdmission::StaleEpoch,
             ::StorageMutationAdmission::SameMode
        error!(VpsAdmin::API::I18n.message('errors.storage_freeze_conflict'), {}, http_status: 409)
      rescue ::StorageMutationAdmission::AuthorizationRefused
        error!(VpsAdmin::API::I18n.message('errors.access_denied'), {}, http_status: 403)
      rescue ArgumentError => e
        raise unless e.message.match?(/catch-up (?:requires read-only mode|freeze epoch changed)/)

        error!(VpsAdmin::API::I18n.message('errors.storage_freeze_conflict'), {}, http_status: 409)
      end
    end
  end
end
