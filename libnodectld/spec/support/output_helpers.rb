# frozen_string_literal: true

module NodeCtldSpec
  module OutputHelpers
    def transaction_output(tx_id)
      raw = sql_value('SELECT output FROM transactions WHERE id = ?', tx_id)
      raw ? JSON.parse(raw) : nil
    end
  end
end
