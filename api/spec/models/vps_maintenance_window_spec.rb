# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VpsMaintenanceWindow do
  around do |example|
    with_current_context(user: SpecSeed.admin) { example.run }
  end

  let(:vps) { create_vps_migration_fixture!(count: 1).fetch(:vpses).first }

  def build_window(weekday:, is_open:, opens_at: nil, closes_at: nil)
    described_class.new(
      vps: vps,
      weekday: weekday,
      is_open: is_open,
      opens_at: opens_at,
      closes_at: closes_at
    )
  end

  it 'requires opens_at and closes_at for open windows' do
    seed_weekly_open_time!(vps, except: 1)
    window = build_window(weekday: 1, is_open: true)

    expect(window).not_to be_valid
    expect(window.errors[:opens_at]).not_to be_empty
    expect(window.errors[:closes_at]).not_to be_empty
  end

  it 'rejects opens_at and closes_at on closed windows' do
    seed_weekly_open_time!(vps, except: 1)
    window = build_window(weekday: 1, is_open: false, opens_at: 0, closes_at: 120)

    expect(window).not_to be_valid
    expect(window.errors[:opens_at]).not_to be_empty
    expect(window.errors[:closes_at]).not_to be_empty
  end

  it 'rejects negative opens_at' do
    seed_weekly_open_time!(vps, except: 1)
    window = build_window(weekday: 1, is_open: true, opens_at: -1, closes_at: 120)

    expect(window).not_to be_valid
    expect(window.errors[:opens_at]).not_to be_empty
  end

  it 'rejects opens_at at or after 24:00' do
    seed_weekly_open_time!(vps, except: 1)
    window = build_window(weekday: 1, is_open: true, opens_at: 24 * 60, closes_at: 24 * 60)

    expect(window).not_to be_valid
    expect(window.errors[:opens_at]).not_to be_empty
  end

  it 'requires closes_at to be after opens_at' do
    seed_weekly_open_time!(vps, except: 1)
    window = build_window(weekday: 1, is_open: true, opens_at: 120, closes_at: 60)

    expect(window).not_to be_valid
    expect(window.errors[:closes_at]).not_to be_empty
  end

  it 'rejects closes_at after 24:00' do
    seed_weekly_open_time!(vps, except: 1)
    window = build_window(weekday: 1, is_open: true, opens_at: 0, closes_at: (24 * 60) + 1)

    expect(window).not_to be_valid
    expect(window.errors[:closes_at]).not_to be_empty
  end

  it 'requires each open window to be at least 60 minutes long' do
    seed_weekly_open_time!(vps, except: 1)
    window = build_window(weekday: 1, is_open: true, opens_at: 0, closes_at: 59)

    expect(window).not_to be_valid
    expect(window.errors[:closes_at]).to include(/60 minutes/)
  end

  it 'requires at least 12 open hours per week' do
    (0..6).each do |weekday|
      create_maintenance_window!(
        vps: vps,
        weekday: weekday,
        is_open: false,
        validate: false
      )
    end

    window = described_class.find_by!(vps: vps, weekday: 1)
    window.assign_attributes(is_open: true, opens_at: 60, closes_at: 120)

    expect(window).not_to be_valid
    expect(window.errors[:closes_at]).to include(/12 hours/)
  end

  it 'builds only open temporary windows for a finish time today' do
    allow(Time).to receive(:now).and_return(Time.utc(2026, 4, 27, 10, 0, 0))

    windows = described_class.make_for(vps, finish_weekday: 1, finish_minutes: 180)

    expect(windows).to all(have_attributes(is_open: true))
    expect(windows.map(&:weekday)).to contain_exactly(0, 1, 2, 3, 4, 5, 6)
    expect(windows.find { |w| w.weekday == 1 }.opens_at).to eq(180)
  end

  it 'builds temporary windows when the finish day is later this week' do
    allow(Time).to receive(:now).and_return(Time.utc(2026, 4, 27, 10, 0, 0))

    windows = described_class.make_for(vps, finish_weekday: 3, finish_minutes: 240)

    expect(windows).to all(have_attributes(is_open: true))
    expect(windows.map(&:weekday)).to contain_exactly(0, 3, 4, 5, 6)
    expect(windows.find { |w| w.weekday == 3 }.opens_at).to eq(240)
  end

  it 'builds temporary windows when the finish day is next week' do
    allow(Time).to receive(:now).and_return(Time.utc(2026, 5, 1, 10, 0, 0))

    windows = described_class.make_for(vps, finish_weekday: 2, finish_minutes: 300)

    expect(windows).to all(have_attributes(is_open: true))
    expect(windows.map(&:weekday)).to contain_exactly(2, 3, 4)
    expect(windows.find { |w| w.weekday == 2 }.opens_at).to eq(300)
  end
end
