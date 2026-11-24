module IncidentPolicyReadHelpers
  def read_report(vps, detected_at:, evaluated_at: detected_at, key: 'category', snapshot: {})
    report = IncidentReport.create!(user: vps.user, vps:, codename: 'manual_abuse', subject: 'Source', text: 'evidence', detected_at:)
    evaluation = report.incident_policy_evaluations.find_by!(policy_key: key)
    IncidentPolicyEvaluation.where(incident_report_id: report.id).update_all(evaluated_at:)
    saved = evaluation.snapshot.deep_merge(snapshot)
    IncidentPolicyEvaluation.where(id: evaluation.id).update_all(snapshot: saved, evaluated_at:)
    [report, evaluation.reload]
  end

  def read_action(evaluation, **attributes)
    report = evaluation.incident_report
    VpsIncidentAction.create!(vps_id: report.vps_id, user_id: report.user_id, incident_report: report,
                              incident_policy_evaluation: evaluation, policy_key: evaluation.policy_key,
                              kind: 'stop', incident_count_7d: 2, incident_count_30d: 4, **attributes)
  end

  def read_stop_chain(vps, finished_at:)
    chain = TransactionChains::Vps::Update.create!(name: 'update', state: :done, user: SpecSeed.admin, size: 1)
    transaction = Transaction.create!(transaction_chain: chain, handle: 1002, node: vps.node, queue: 'vps')
    transaction.update_columns(done: 1, status: 1, finished_at:)
    chain
  end
end

RSpec.configure { |config| config.include IncidentPolicyReadHelpers }
