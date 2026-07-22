# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EventTimeInterval do
  def build_interval(specs:, time_zone: 'UTC', user: SpecSeed.user, name: 'Spec interval')
    described_class.new(user:, name:, time_zone:, specs:)
  end

  it 'matches all configured calendar dimensions with inclusive starts and exclusive time ends' do
    interval = build_interval(
      specs: [
        {
          times: [{ start_time: '09:00', end_time: '17:00' }],
          weekdays: [{ start: 'monday', end: 'friday' }],
          days_of_month: [{ start: 20, end: 25 }],
          months: [{ start: 7, end: 7 }],
          years: [{ start: 2024, end: 2024 }]
        }
      ]
    )

    expect(interval).to be_valid
    expect(interval.matches?(Time.utc(2024, 7, 22, 9, 0))).to be(true)
    expect(interval.matches?(Time.utc(2024, 7, 22, 16, 59, 59))).to be(true)
    expect(interval.matches?(Time.utc(2024, 7, 22, 17, 0))).to be(false)
    expect(interval.matches?(Time.utc(2024, 7, 27, 12, 0))).to be(false)
  end

  it 'combines specifications and ranges with OR while dimensions use AND' do
    interval = build_interval(
      specs: [
        {
          weekdays: [{ start: 'monday' }, { start: 'wednesday' }],
          years: [{ start: 2025 }]
        },
        {
          months: [{ start: 12 }],
          years: [{ start: 2026 }]
        }
      ]
    )

    expect(interval).to be_valid
    expect(interval.matches?(Time.utc(2025, 1, 6, 12, 0))).to be(true)
    expect(interval.matches?(Time.utc(2025, 1, 7, 12, 0))).to be(false)
    expect(interval.matches?(Time.utc(2026, 12, 15, 12, 0))).to be(true)
  end

  it 'evaluates negative days of month and the configured IANA time zone' do
    last_day = build_interval(
      specs: [{ days_of_month: [{ start: -1 }] }],
      time_zone: 'Europe/Prague'
    )
    local_business_hour = build_interval(
      specs: [{ times: [{ start_time: '09:00', end_time: '10:00' }] }],
      time_zone: 'Europe/Prague',
      name: 'Prague business hour'
    )

    expect(last_day).to be_valid
    expect(last_day.matches?(Time.utc(2026, 2, 28, 12, 0))).to be(true)
    expect(last_day.matches?(Time.utc(2026, 2, 27, 12, 0))).to be(false)
    expect(local_business_hour).to be_valid
    expect(local_business_hour.matches?(Time.utc(2026, 1, 5, 8, 0))).to be(true)
    expect(local_business_hour.matches?(Time.utc(2026, 1, 5, 9, 0))).to be(false)
  end

  it 'defaults the time zone from the interval owner' do
    user = SpecSeed.user
    user.update!(time_zone: 'Europe/Prague')
    interval = build_interval(
      specs: [{ weekdays: [{ start: 'monday' }] }],
      time_zone: nil,
      user:
    )

    expect(interval).to be_valid
    expect(interval.time_zone).to eq('Europe/Prague')
  end

  it 'locks the owner while creating a bounded reusable interval' do
    user = SpecSeed.user
    allow(user).to receive(:lock!).and_call_original

    interval = described_class.create_for_user!(
      user:,
      name: 'Serialized interval',
      time_zone: 'UTC',
      specs: [{ years: [{ start: 2026 }] }]
    )

    expect(interval).to be_persisted
    expect(user).to have_received(:lock!)
  end

  it 'rejects empty, overnight, wrapped and unknown interval input' do
    empty = build_interval(specs: [])
    overnight = build_interval(
      specs: [{ times: [{ start_time: '23:00', end_time: '01:00' }] }]
    )
    wrapped_weekdays = build_interval(
      specs: [{ weekdays: [{ start: 'friday', end: 'monday' }] }]
    )
    unknown = build_interval(specs: [{ unsupported: [{ start: 1 }] }])

    expect(empty).not_to be_valid
    expect(overnight).not_to be_valid
    expect(wrapped_weekdays).not_to be_valid
    expect(unknown).not_to be_valid
    expect(overnight.errors[:specs].join).to include('must end after it starts')
  end

  it 'limits specifications and ranges to bounded input sizes' do
    too_many_specs = build_interval(
      specs: Array.new(described_class::MAX_SPECS + 1) do
        { years: [{ start: 2026 }] }
      end
    )
    too_many_ranges = build_interval(
      specs: [
        {
          years: Array.new(described_class::MAX_RANGES_PER_DIMENSION + 1) do |index|
            { start: 2000 + index }
          end
        }
      ]
    )

    expect(too_many_specs).not_to be_valid
    expect(too_many_ranges).not_to be_valid
    expect(too_many_specs.errors[:specs].join).to include('cannot contain more than')
    expect(too_many_ranges.errors[:specs].join).to include('ranges')
  end

  it 'limits the number of reusable intervals owned by one user' do
    now = Time.now
    described_class.insert_all!(
      Array.new(described_class::MAX_INTERVALS_PER_USER) do |index|
        {
          user_id: SpecSeed.user.id,
          name: "Existing interval #{index}",
          time_zone: 'UTC',
          specs: JSON.dump([{ years: [{ start: 2026 }] }]),
          created_at: now,
          updated_at: now
        }
      end
    )
    overflow = build_interval(
      name: 'Overflow interval',
      specs: [{ years: [{ start: 2026 }] }]
    )

    expect(overflow).not_to be_valid
    expect(overflow.errors[:base].join).to include('cannot have more than')
  end

  it 'requires route assignments to have the same owner and blocks referenced interval deletion' do
    interval = build_interval(specs: [{ years: [{ start: 2026 }] }])
    interval.save!
    own_route = EventRoute.create!(
      user: SpecSeed.user,
      event_type: 'user.test_notification',
      position: 1
    )
    foreign_route = EventRoute.create!(
      user: SpecSeed.other_user,
      event_type: 'user.test_notification',
      position: 1
    )

    foreign_assignment = EventRouteTimeInterval.new(
      event_route: foreign_route,
      event_time_interval: interval,
      mode: :active
    )

    lock_order = []
    allow(interval).to receive(:lock!).and_wrap_original do |method|
      lock_order << :interval
      method.call
    end
    allow(own_route).to receive(:lock!).and_wrap_original do |method|
      lock_order << :route
      method.call
    end
    own_assignment = EventRouteTimeInterval.assign!(
      event_route: own_route,
      event_time_interval: interval,
      mode: :active
    )

    expect(own_assignment).to be_persisted
    expect(lock_order).to eq(%i[interval route])
    expect(foreign_assignment).not_to be_valid
    expect(interval.destroy).to be(false)
    expect(interval.errors[:base]).to be_present
  end

  it 'limits the number of assignments on one route' do
    route = EventRoute.create!(
      user: SpecSeed.user,
      event_type: 'user.test_notification',
      position: 1
    )
    EventRoute::MAX_TIME_INTERVALS.times do |index|
      interval = build_interval(
        name: "Limit interval #{index}",
        specs: [{ years: [{ start: 2026 }] }]
      )
      interval.save!
      route.event_route_time_intervals.create!(
        event_time_interval: interval,
        mode: :active
      )
    end
    overflow = build_interval(
      name: 'Overflow interval',
      specs: [{ years: [{ start: 2026 }] }]
    )
    overflow.save!
    assignment = route.event_route_time_intervals.new(
      event_time_interval: overflow,
      mode: :active
    )

    expect(assignment).not_to be_valid
    expect(assignment.errors[:base].join).to include('cannot assign more than')
  end
end
