module VpsAdmin::API::Operations::Node::HistoryBackfill
  DEFAULT_BATCH_SIZE = 10_000
  MAX_SCAN_RETRIES = 3
  RETRY = Object.new.freeze

  class ConcurrentChange < StandardError; end

  protected

  def validate_batch_size(batch_size)
    value = Integer(batch_size)
    raise ArgumentError, 'batch size must be a positive integer' unless value > 0

    value
  rescue ArgumentError, TypeError
    raise ArgumentError, 'batch size must be a positive integer'
  end

  def status_watermark(node)
    ::NodeStatus.where(node_id: node.id).maximum(:id)
  end

  def ordered_status_ids(node, watermark:, before: nil)
    return [] unless watermark

    scope = ::NodeStatus.where(node_id: node.id, id: ..watermark)
                        .where.not(created_at: nil)
    scope = scope.where('created_at < ?', before) if before
    scope.order(:created_at, :id).pluck(:id)
  end

  def each_status_batch(status_ids, columns, batch_size)
    status_ids.each_slice(batch_size) do |batch_ids|
      rows = ::NodeStatus.where(id: batch_ids).pluck(:id, *columns)
      rows_by_id = rows.to_h { |row| [row.first, row] }
      ordered_rows = batch_ids.filter_map { |id| rows_by_id[id] }
      if ordered_rows.length != batch_ids.length
        raise ConcurrentChange, 'selected Node status rows changed during the unlocked scan'
      end

      yield ordered_rows
    end
  end

  def retry_scan!(progress, retries, reason)
    if retries >= MAX_SCAN_RETRIES
      progress&.failed(reason:)
      raise ConcurrentChange,
            "Node history changed during #{MAX_SCAN_RETRIES + 1} consecutive scans"
    end

    progress&.retry(reason:)
    retries + 1
  end
end
