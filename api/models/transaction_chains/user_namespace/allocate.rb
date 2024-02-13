module TransactionChains
  class UserNamespace::Allocate < ::TransactionChain
    label 'Allocate userns'

    AvailableRange = Struct.new(:first, :last) do
      def blocks
        t = ::UserNamespaceBlock.table_name

        ::UserNamespaceBlock.where(
          "#{t}.index >= ? AND #{t}.index <= ?", first.index, last.index
        ).order("#{t}.index")
      end
    end

    def link_chain(user, block_count)
      blocks = allocate_block_range(block_count)

      uns = ::UserNamespace.create!(
        user:,
        block_count:,
        offset: blocks.first.offset,
        size: blocks.inject(0) { |sum, block| sum + block.size }
      )
      blocks.each { |blk| blk.update!(user_namespace: uns) }

      lock(uns)

      confirmations = proc do |t|
        t.just_create(uns)
        blocks.each { |blk| t.edit_before(blk, user_namespace_id: nil) }
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id, &confirmations)

      uns
    end

    protected

    def allocate_block_range(count)
      ranges = available_ranges(count)
      locks = []

      ranges.each do |range|
        locks << lock(range.first)
        locks << lock(range.last)

        blocks = range.blocks
        blocks.each { |blk| locks << lock(blk) }

        if blocks.detect(&:user_namespace_id)
          locks.each(&:release).clear
          next
        end

        return blocks
      rescue ResourceLocked
        locks.each(&:release).clear
        next
      end

      raise 'unable to find free block range'
    end

    def available_ranges(block_count)
      res = ::UserNamespaceBlock.connection.execute("
        SELECT
          b1.id, b1.index, b2.id, b2.index

        FROM
          user_namespace_blocks b1,
          user_namespace_blocks b2

        WHERE
          b1.user_namespace_id IS NULL
          AND
          b2.user_namespace_id IS NULL
          AND
          b1.id != b2.id
          AND
          b1.index + #{block_count - 1} = b2.index
          AND
          (
            SELECT COUNT(*)
            FROM user_namespace_blocks b3
            WHERE
              b3.index >= b1.index
              AND
              b3.index <= b2.index
              AND
              b3.user_namespace_id IS NOT NULL
          ) = 0

        ORDER BY b1.index
        LIMIT #{block_count * 2}
      ")

      res.map do |row|
        f_id, f_index, l_id, l_index = row

        AvailableRange.new(
          ::UserNamespaceBlock.new(id: f_id, index: f_index),
          ::UserNamespaceBlock.new(id: l_id, index: l_index)
        )
      end
    end
  end
end
