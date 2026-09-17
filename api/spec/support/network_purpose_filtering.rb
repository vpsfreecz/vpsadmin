# frozen_string_literal: true

RSpec.shared_examples 'network purpose filtering' do |resource|
  let(:purpose_networks) do
    %w[any vps export].each_with_index.to_h do |purpose, index|
      network = Network.create!(
        label: "Purpose #{purpose}", address: "198.51.100.#{64 * (index + 1)}",
        prefix: 26, ip_version: 4, role: :public_access, managed: true,
        split_access: :no_access, split_prefix: 32, purpose:,
        primary_location: SpecSeed.location
      )
      LocationNetwork.create!(network:, location: SpecSeed.location,
                              primary: true, priority: 20, autopick: false, userpick: true)
      [purpose, network]
    end
  end

  def purpose_result_ids(resource)
    json.fetch('response').fetch(resource.to_s.pluralize).map { |row| row.fetch('id') }
  end

  before { purpose_records }

  %i[admin user].each do |actor|
    %w[vps export].each do |purpose|
      it "includes any and #{purpose} networks for #{actor}" do
        as(SpecSeed.public_send(actor)) { json_get index_path, resource => { usable_for: purpose } }

        expect_status(200)
        expect(json['status']).to be(true)
        ids = purpose_result_ids(resource) & purpose_records.values.map(&:id)
        expect(ids).to contain_exactly(purpose_records.fetch('any').id, purpose_records.fetch(purpose).id)
      end
    end
  end

  %w[any vps export].each do |purpose|
    it "keeps purpose=#{purpose} exact" do
      as(SpecSeed.admin) { json_get index_path, resource => { purpose: } }

      expect_status(200)
      ids = purpose_result_ids(resource) & purpose_records.values.map(&:id)
      expect(ids).to contain_exactly(purpose_records.fetch(purpose).id)
    end
  end

  it 'does not restrict purpose when both filters are omitted' do
    as(SpecSeed.admin) { json_get index_path }

    expect(purpose_result_ids(resource)).to include(*purpose_records.values.map(&:id))
  end

  it 'intersects exact purpose with compatibility' do
    as(SpecSeed.admin) { json_get index_path, resource => { purpose: 'any', usable_for: 'vps' } }
    expect(purpose_result_ids(resource) & purpose_records.values.map(&:id))
      .to contain_exactly(purpose_records.fetch('any').id)

    as(SpecSeed.admin) { json_get index_path, resource => { purpose: 'export', usable_for: 'vps' } }
    expect(purpose_result_ids(resource)).to be_empty
  end

  it 'filters before pagination and reports the filtered count' do
    as(SpecSeed.admin) { json_get index_path, resource => { usable_for: 'vps', limit: 100 } }
    expected_ids = purpose_result_ids(resource)

    as(SpecSeed.admin) do
      json_get index_path, resource => { usable_for: 'vps', limit: 1 }, _meta: { count: true }
    end
    expect(purpose_result_ids(resource)).to eq(expected_ids.take(1))
    expect(json.dig('response', '_meta', 'total_count')).to eq(expected_ids.size)

    as(SpecSeed.admin) do
      json_get index_path, resource => { usable_for: 'vps', limit: 1, from_id: expected_ids.first }
    end
    expect(purpose_result_ids(resource)).to eq(expected_ids.drop(1).take(1))
  end

  %w[any unknown].each do |value|
    it "rejects usable_for=#{value}" do
      as(SpecSeed.admin) { json_get index_path, resource => { usable_for: value } }

      expect(json['status']).to be(false)
      expect(json.fetch('errors')).to have_key('usable_for')
    end
  end
end
