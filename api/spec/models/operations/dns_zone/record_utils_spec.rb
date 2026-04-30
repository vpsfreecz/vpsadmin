# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsAdmin::API::Operations::DnsZone::RecordUtils do
  subject(:helper) do
    Class.new do
      include VpsAdmin::API::Operations::DnsZone::RecordUtils
    end.new
  end

  it 'strips record content' do
    expect(helper.process_record({ record_type: 'A', content: ' 198.51.100.10 ' })).to include(
      content: '198.51.100.10'
    )
  end

  it 'extracts priority from MX and SRV content' do
    expect(helper.process_record({ record_type: 'MX', content: '10 mail.example.test' })).to include(
      priority: 10,
      content: 'mail.example.test.'
    )
    expect(helper.process_record({ record_type: 'SRV', content: '20 service.example.test' })).to include(
      priority: 20,
      content: 'service.example.test.'
    )
  end

  it 'ensures domain-valued content is fully qualified' do
    expect(helper.process_record({ record_type: 'CNAME', content: 'target.example.test' })).to include(
      content: 'target.example.test.'
    )
  end

  it 'returns attributes unchanged when content is not present' do
    attrs = { record_type: 'TXT', ttl: 600 }

    expect(helper.process_record(attrs)).to eq(attrs)
  end
end
