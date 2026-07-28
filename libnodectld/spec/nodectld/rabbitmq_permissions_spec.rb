require 'open3'
require 'rbconfig'
require_relative '../../../tools/rabbitmqcfg'

RSpec.describe Cli do
  def permissions_for(type, user)
    script = File.expand_path('../../../tools/rabbitmqcfg.rb', __dir__)
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby,
      script,
      'user',
      '--perms',
      type,
      user
    )

    expect(status).to be_success, stderr

    stdout.scan(/"([^"]+)"/).flatten.map { |pattern| Regexp.new(pattern) }
  end

  it 'allows the console router to declare and publish to control exchanges' do
    configure, write, = permissions_for('console', 'console')

    expect(configure).to match('console:node1.example.test:control')
    expect(write).to match('console:node1.example.test:control')
  end

  it 'allows nodes to bind and read their own control queue' do
    _configure, _write, read = permissions_for('node', 'node1.example.test')

    expect(read).to match('console:node1.example.test:control')
    expect(read).not_to match('console:node2.example.test:control')
  end
end
