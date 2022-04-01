require 'libosctl'
require 'yaml'

module NodeCtld
  class Confirmations
    include OsCtl::Lib::Utils::Log

    def self.translate_type(t)
      [
        :create,
        :just_create,
        :edit_before,
        :edit_after,
        :destroy,
        :just_destroy,
        :decrement,
        :increment
      ][t]
    end

    def initialize(chain_id)
      @chain_id = chain_id
    end

    def run(t, direction)
      log(:debug, "chain=#{@chain_id}", 'Running transaction confirmations')

      rs = t.prepared(
        'SELECT table_name, row_pks, attr_changes, confirm_type, t.status
          FROM transactions t
          INNER JOIN transaction_confirmations c ON t.id = c.transaction_id
          WHERE
            t.transaction_chain_id = ?
            AND c.done = 0',
        @chain_id
      )

      rs.each do |trans|
        confirm(t, trans, direction)
      end

      t.prepared(
        'UPDATE transaction_confirmations c
        INNER JOIN transactions t ON t.id = c.transaction_id
        SET c.done = 1
        WHERE t.transaction_chain_id = ? AND c.done = 0',
        @chain_id
      )
    end

    def force_run(t, transactions, direction, success)
      log(:debug, "chain=#{@chain_id}", 'Running transaction confirmations forcefully')
      log(:debug, "chain=#{@chain_id}", "Transactions: #{transactions.join(',')}")

      ret = {}

      rs = t.query(
        "SELECT table_name, row_pks, attr_changes, confirm_type, t.status,
                c.done, c.id AS c_id, t.id AS t_id, class_name
          FROM transactions t
          INNER JOIN transaction_confirmations c ON t.id = c.transaction_id
          WHERE
            t.transaction_chain_id = #{@chain_id}
            AND t.id IN (#{transactions.join(',')})
      ")

      rs.each do |trans|
        ret[ trans['t_id'].to_i ] ||= []
        ret[ trans['t_id'].to_i ] << {
          id: trans['c_id'].to_i,
          class_name: trans['class_name'],
          row_pks: load_yaml(trans['row_pks']),
          attr_changes: trans['attr_changes'] ? load_yaml(trans['attr_changes']) : nil,
          type: self.class.translate_type(trans['confirm_type'].to_i),
          done: trans['done'].to_i == 1 ? true : false,
        }

        confirm(t, trans, direction, success)
      end

      t.query(
        "UPDATE transaction_confirmations c
          INNER JOIN transactions t ON t.id = c.transaction_id
          SET c.done = 1
          WHERE t.transaction_chain_id = #{@chain_id}
                AND t.id IN (#{transactions.join(',')})
      ")

      ret
    end

    protected
    def confirm(t, trans, dir, success = nil)
      success = success.nil? ? trans['status'].to_i > 0 : success
      pk = pk_cond(load_yaml(trans['row_pks']))

      case trans['confirm_type'].to_i
      when 0 # create
        if success && dir == :execute
          t.query("UPDATE #{trans['table_name']} SET confirmed = 1 WHERE #{pk}")
        else
          t.query("DELETE FROM #{trans['table_name']} WHERE #{pk}")
        end

      when 1 # just create
        if !success || dir != :execute
          t.query("DELETE FROM #{trans['table_name']} WHERE #{pk}")
        end

      when 2 # edit before
        if !success || dir == :rollback
          attrs = load_yaml(trans['attr_changes'])
          update = attrs.collect { |k, v| "`#{k}` = #{sql_val(v)}" }.join(',')

          t.query("UPDATE #{trans['table_name']} SET #{update} WHERE #{pk}")
        end

      when 3 # edit after
        if success && dir == :execute
          attrs = load_yaml(trans['attr_changes'])
          update = attrs.collect { |k, v| "`#{k}` = #{sql_val(v)}" }.join(',')

          t.query("UPDATE #{trans['table_name']} SET #{update} WHERE #{pk}")
        end

      when 4 # destroy
        if success && dir == :execute
          t.query("DELETE FROM #{trans['table_name']} WHERE #{pk}")
        else
          t.query("UPDATE #{trans['table_name']} SET confirmed = 1 WHERE #{pk}")
        end

      when 5 # just destroy
        if success && dir == :execute
          t.query("DELETE FROM #{trans['table_name']} WHERE #{pk}")
        end

      when 6 # decrement
        if success && dir == :execute
          attr = load_yaml(trans['attr_changes'])

          t.query("UPDATE #{trans['table_name']} SET #{attr} = #{attr} - 1 WHERE #{pk}")
        end

      when 7 # increment
        if success && dir == :execute
          attr = load_yaml(trans['attr_changes'])

          t.query("UPDATE #{trans['table_name']} SET #{attr} = #{attr} + 1 WHERE #{pk}")
        end
      end
    end

    def load_yaml(v)
      YAML.safe_load(v, permitted_classes: [Symbol, Time])
    end

    def pk_cond(pks)
      pks.map { |k, v| "`#{k}` = #{sql_val(v)}" }.join(' AND ')
    end

    def sql_val(v)
      if v.is_a?(Integer)
        v
      elsif v.nil?
        'NULL'
      elsif v.is_a?(::Time)
        "'#{v.utc.strftime('%Y-%m-%d %H:%M:%S')}'"
      else
        "'#{v}'"
      end
    end
  end
end
