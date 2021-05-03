require 'tempfile'

module NodeCtld
  module Utils::MBuffer
    def mbuffer_log_file
      @mbuffer_log_file ||= File.join(
        ENV['TMPDIR'] || '/tmp',
        "nodectld-mbuffer-#{@command.id}.log",
      )
    end

    def mbuffer_cleanup_log_file
      File.unlink(mbuffer_log_file)
    rescue Errno::ENOENT
    end
  end
end
