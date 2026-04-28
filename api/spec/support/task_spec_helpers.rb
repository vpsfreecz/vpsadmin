# frozen_string_literal: true

require 'stringio'

module TaskSpecHelpers
  def capture_streams
    old_stdout = $stdout
    old_stderr = $stderr
    out = StringIO.new
    err = StringIO.new
    $stdout = out
    $stderr = err

    yield

    [out.string, err.string]
  ensure
    $stdout = old_stdout
    $stderr = old_stderr
  end
end

RSpec.configure do |config|
  config.include TaskSpecHelpers
end
