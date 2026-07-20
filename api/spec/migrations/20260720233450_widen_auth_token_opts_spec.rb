# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260720233450_widen_auth_token_opts')

RSpec.describe WidenAuthTokenOpts do
  before do
    define_schema do
      create_table :auth_tokens do |t|
        t.string :opts
      end
    end
  end

  it 'stores authentication continuation options larger than a string column' do
    migrate_up!

    expect(column(:auth_tokens, :opts)).to have_attributes(type: :text, limit: 65_535, null: true)

    opts = "{\"scope\":\"#{'node_kernel_evidence#index ' * 40}\"}"
    id = insert_row(:auth_tokens, opts:)

    expect(find_row(:auth_tokens, id:).fetch('opts')).to eq(opts)
  end

  it 'restores the original string column on rollback' do
    migrate_up!
    id = insert_row(:auth_tokens, opts: '{"scope":["all"]}')

    migrate_down!

    expect(column(:auth_tokens, :opts)).to have_attributes(type: :string, limit: 255, null: true)
    expect(find_row(:auth_tokens, id:).fetch('opts')).to eq('{"scope":["all"]}')
  end
end
