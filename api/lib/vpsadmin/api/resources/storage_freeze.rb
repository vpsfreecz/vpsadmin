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
        matching = control.epoch == snapshot.fetch(:epoch) && control.mode == snapshot.fetch(:mode) &&
                   ::StorageFreezeStatus.maintenance_summary(control) == snapshot.fetch(:active_maintenance)
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

      def maintenance_request
        yield.summary
      rescue ::StorageMutationAdmission::StaleEpoch, ::StorageMutationAdmission::MaintenanceConflict,
             ::StorageMaintenanceRun::UnsupportedRecord, ActiveRecord::RecordNotFound
        error!(VpsAdmin::API::I18n.message('errors.storage_freeze_conflict'), {}, http_status: 409)
      rescue ArgumentError
        error!(VpsAdmin::API::I18n.message('errors.storage_freeze_invalid_request'), {}, http_status: 422)
      rescue ::StorageMutationAdmission::AuthorizationRefused
        error!(VpsAdmin::API::I18n.message('errors.access_denied'), {}, http_status: 403)
      end

      def change_mode(read_only:)
        ::StorageMutationAdmission.set_read_only_for_user!(
          read_only:, expected_epoch: input[:expected_epoch],
          reason: input[:reason], user: current_user,
          user_session: ::UserSession.current
        )
        status
      rescue ::StorageMutationAdmission::StaleEpoch, ::StorageMutationAdmission::SameMode,
             ::StorageMutationAdmission::MaintenanceConflict, ::StorageMaintenanceRun::UnsupportedRecord
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
      custom :active_maintenance, nullable: true, label: 'Active API maintenance reservation'
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
      rescue ::StorageMaintenanceRun::UnsupportedRecord, ActiveRecord::RecordNotFound
        error!(VpsAdmin::API::I18n.message('errors.storage_freeze_conflict'), {}, http_status: 409)
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

    params(:maintenance_identity) do
      string :request_id, required: true, label: 'Maintenance request UUID',
                          desc: 'Canonical client UUID identifying this API-only reservation'
    end

    params(:maintenance_result) do
      integer :id
      string :request_id, label: 'Maintenance request UUID'
      integer :record_contract, label: 'Maintenance record contract'
      string :requested_profile, label: 'Requested maintenance profile'
      string :state
      integer :revision
      integer :freeze_epoch, label: 'Reserved storage mode epoch'
      custom :requested_pool_ids, label: 'Requested storage pool IDs'
      string :requested_scope_digest, label: 'Requested catalog scope digest'
      integer :acquired_by_user_id, label: 'Acquiring administrator ID'
      integer :acquired_by_user_session_id, label: 'Acquiring administrator session ID'
      string :acquired_by_user_login, label: 'Acquiring administrator login'
      string :acquisition_reason, label: 'Reservation reason'
      datetime :acquired_at, label: 'Reserved at'
      integer :abandoned_by_user_id, nullable: true, label: 'Abandoning administrator ID'
      integer :abandoned_by_user_session_id, nullable: true, label: 'Abandoning administrator session ID'
      string :abandoned_by_user_login, nullable: true, label: 'Abandoning administrator login'
      string :abandonment_reason, nullable: true, label: 'Abandonment reason'
      datetime :abandoned_at, nullable: true, label: 'Abandoned at'
      integer :handed_off_by_user_id, nullable: true, label: 'Responsible administrator ID'
      integer :handed_off_by_user_session_id, nullable: true, label: 'Responsible administrator session ID'
      string :handed_off_by_user_login, nullable: true, label: 'Administrator login at handoff'
      string :handoff_reason, nullable: true, label: 'Handoff reason'
      datetime :handed_off_at, nullable: true, label: 'Responsibility acknowledged at'
    end

    class MaintenanceReserve < HaveAPI::Action
      include Access

      route 'maintenance_reserve'
      http_method :post
      desc 'Reserve API storage admission without acquiring physical maintenance ownership'
      input do
        use :maintenance_identity
        use :change, include: [:expected_epoch]
        text :reason, required: true, desc: 'Reason for the API maintenance reservation'
        custom :pool_ids, required: true, label: 'Requested storage pools',
                          desc: 'Array of 1 to 256 distinct positive integer Pool IDs to snapshot under the maintenance reservation lock'
      end
      output { use :maintenance_result }
      authorize { |user| allow if Access.allowed?(user) }

      def exec
        maintenance_request do
          ::StorageMutationAdmission.reserve_maintenance_for_user!(
            request_id: input[:request_id], expected_epoch: input[:expected_epoch],
            pool_ids: input[:pool_ids], reason: input[:reason],
            user: current_user, user_session: ::UserSession.current
          )
        end
      end
    end

    class MaintenanceShow < HaveAPI::Action
      include Access

      route 'maintenance_show'
      http_method :get
      desc 'Inspect retained maintenance responsibility by UUID'
      input { use :maintenance_identity }
      output { use :maintenance_result }
      authorize { |user| allow if Access.allowed?(user) }

      def exec
        maintenance_request do
          ::StorageMutationAdmission.show_maintenance_for_user!(
            request_id: input[:request_id], user: current_user, user_session: ::UserSession.current
          )
        end
      end
    end

    class MaintenanceHandoff < HaveAPI::Action
      include Access

      route 'maintenance_handoff'
      http_method :post
      desc 'Acknowledge responsibility for a prospective transition without acquiring physical ownership'
      input do
        use :maintenance_identity
        use :change, include: [:expected_epoch]
        integer :expected_contract, required: true, label: 'Expected maintenance record contract',
                                    desc: 'API-only predecessor contract, which must be 1'
        integer :expected_revision, required: true, label: 'Expected maintenance revision',
                                    desc: 'API-only predecessor revision, which must be 1'
        string :expected_scope_digest, required: true, label: 'Expected requested catalog scope digest',
                                       desc: 'Digest returned by maintenance_show; changed catalog claims refuse handoff'
        text :reason, required: true, desc: 'Reason for accepting prospective maintenance responsibility'
      end
      output { use :maintenance_result }
      authorize { |user| allow if Access.allowed?(user) }

      def exec
        maintenance_request do
          ::StorageMutationAdmission.handoff_maintenance_for_user!(
            request_id: input[:request_id], expected_epoch: input[:expected_epoch],
            expected_contract: input[:expected_contract], expected_revision: input[:expected_revision],
            expected_scope_digest: input[:expected_scope_digest], reason: input[:reason],
            user: current_user, user_session: ::UserSession.current
          )
        end
      end
    end

    class MaintenanceAbandon < HaveAPI::Action
      include Access

      route 'maintenance_abandon'
      http_method :post
      desc 'Abandon an API-only reservation while keeping storage read-only'
      input do
        use :maintenance_identity
        use :change, include: [:expected_epoch]
        text :reason, required: true, desc: 'Reason for abandoning the API maintenance reservation'
        integer :expected_revision, required: true, label: 'Expected maintenance revision',
                                    desc: 'Reserved revision returned by maintenance_show'
        string :expected_scope_digest, required: true, label: 'Expected requested catalog scope digest',
                                       desc: 'Digest returned by maintenance_show; changed scope refuses abandonment'
      end
      output { use :maintenance_result }
      authorize { |user| allow if Access.allowed?(user) }

      def exec
        maintenance_request do
          ::StorageMutationAdmission.abandon_maintenance_for_user!(
            request_id: input[:request_id], expected_epoch: input[:expected_epoch],
            expected_revision: input[:expected_revision], expected_scope_digest: input[:expected_scope_digest],
            reason: input[:reason], user: current_user, user_session: ::UserSession.current
          )
        end
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
