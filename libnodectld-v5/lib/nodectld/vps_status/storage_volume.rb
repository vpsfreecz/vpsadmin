module NodeCtld
  class VpsStatus::StorageVolume
    # @return [Integer]
    attr_reader :id

    def initialize(row)
      @id = row['id']
      @pool_path = row['pool_path']
      @name = row['name']
      @format = row['format']

      @read_requests_readout = row['read_requests_readout']
      @read_bytes_readout = row['read_bytes_readout']
      @write_requests_readout = row['write_requests_readout']
      @write_bytes_readout = row['write_bytes_readout']

      @read_requests = 0
      @read_bytes = 0
      @write_requests = 0
      @write_bytes = 0
    end

    def path
      if @id == 'all'
        ''
      else
        File.join(@pool_path, "#{@name}.#{@format}")
      end
    end

    def set(io_stats)
      @read_requests = [io_stats.rd_req - @read_requests_readout, 0].max
      @read_bytes = [io_stats.rd_bytes - @read_bytes_readout, 0].max

      @write_requests = [io_stats.wr_req - @write_requests_readout, 0].max
      @write_bytes = [io_stats.wr_bytes - @write_bytes_readout, 0].max

      @read_requests_readout = io_stats.rd_req
      @read_bytes_readout = io_stats.rd_bytes

      @write_requests_readout = io_stats.wr_req
      @write_bytes_readout = io_stats.wr_bytes
    end

    def export
      {
        'id' => id,
        'read_requests' => @read_requests,
        'read_bytes' => @read_bytes,
        'write_requests' => @write_requests,
        'write_bytes' => @write_bytes,
        'read_requests_readout' => @read_requests_readout,
        'read_bytes_readout' => @read_bytes_readout,
        'write_requests_readout' => @write_requests_readout,
        'write_bytes_readout' => @write_bytes_readout
      }
    end
  end
end
