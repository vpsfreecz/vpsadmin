# frozen_string_literal: true

require 'spec_helper'
require 'nodectld/commands/base'
require 'nodectld/commands/pool/generate_send_key'

RSpec.describe NodeCtld::Commands::Pool::GenerateSendKey do
  let(:driver) { build_storage_driver }
  let!(:pool) { insert_pool!(filesystem: 'tank/spec-send-key') }

  it 'stores the generated public key in the database and clears it on rollback' do
    Dir.mktmpdir('send-key') do |dir|
      pub = File.join(dir, 'id_ed25519.pub')
      priv = File.join(dir, 'id_ed25519')
      File.write(pub, "ssh-ed25519 AAAATEST pool@test\n")
      File.write(priv, 'PRIVATE')

      cmd = described_class.new(driver, 'pool_id' => pool.fetch('id'), 'pool_name' => 'tank')
      allow(NodeCtld::Db).to receive(:new).and_return(shared_db)
      allow(cmd).to receive(:osctl_pool) do |_pool_name, subcmd, *_args|
        case subcmd
        when %i[send key gen]
          double(output: '', exitstatus: 0)
        when %i[send key path public]
          double(output: "#{pub}\n", exitstatus: 0)
        when %i[send key path private]
          double(output: "#{priv}\n", exitstatus: 0)
        else
          raise "unexpected osctl_pool call: #{subcmd.inspect}"
        end
      end

      expect(cmd.exec).to eq(ret: :ok)
      expect(cmd).to have_received(:osctl_pool).with('tank', %i[send key gen], [], { force: true })
      expect(sql_value('SELECT migration_public_key FROM pools WHERE id = ?', pool.fetch('id')))
        .to eq('ssh-ed25519 AAAATEST pool@test')

      expect(cmd.rollback).to eq(ret: :ok)
      expect(sql_value('SELECT migration_public_key FROM pools WHERE id = ?', pool.fetch('id'))).to be_nil
      expect(File.exist?(pub)).to be(false)
      expect(File.exist?(priv)).to be(false)

      expect(cmd.rollback).to eq(ret: :ok)
    end
  end
end
