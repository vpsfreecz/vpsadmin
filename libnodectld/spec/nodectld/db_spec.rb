# frozen_string_literal: true

RSpec.describe NodeCtld::Db do
  describe 'database connection' do
    it 'explicitly disables TLS' do
      client = instance_double(Mysql2::Client, query: nil)
      db_config = {
        hosts: ['127.0.0.1'],
        host: nil,
        user: 'nodectld',
        pass: 'secret',
        name: 'vpsadmin',
        connect_timeout: 15,
        read_timeout: 15,
        write_timeout: 15
      }

      allow(Mysql2::Client).to receive(:new).and_return(client)

      described_class.new(db_config)

      expect(Mysql2::Client).to have_received(:new).with(
        host: '127.0.0.1',
        username: 'nodectld',
        password: 'secret',
        database: 'vpsadmin',
        encoding: 'utf8',
        connect_timeout: 15,
        read_timeout: 15,
        write_timeout: 15,
        ssl_mode: :disabled,
        database_timezone: :utc
      )
    end
  end
end
