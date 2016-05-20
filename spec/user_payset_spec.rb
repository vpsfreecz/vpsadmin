require "json"
require "selenium-webdriver"
require "rspec"
include RSpec::Expectations

describe 'User payset' do
  # TODO: find a better way of inputting credentials
  USERNAME = ''
  PASSWORD = ''
  USER_ID = 1754

  before(:all) do
    @driver = Selenium::WebDriver.for(:firefox)
    @driver.manage.timeouts.implicit_wait = 5
    @base_url = "https://vpsadmin.vpsfree.cz/"
    @driver.get(@base_url)
    login
    @driver.get("#{@base_url}/?page=adminm&section=members&action=payset&id=#{USER_ID}")
  end

  after(:all) do
    logout
    @driver.quit
  end

  def login
    expect(USERNAME.length).to be > 0
    expect(PASSWORD.length).to be > 0

    @driver.find_element(
        :css,
        'form[action="?page=login&action=login"] input[name="username"]'
    ).send_keys(USERNAME)

    @driver.find_element(
        :css,
        'form[action="?page=login&action=login"] input[name="passwd"]'
    ).send_keys(PASSWORD)

    @driver.find_element(
        :css,
        'form[action="?page=login&action=login"] input[type="submit"]'
    ).click

    expect(@driver.find_element(
        :css,
        'form[action="?page=login&action=logout"] input[type="submit"]'
    ).attribute(:value)).to eq("Logout (#{USERNAME})")
  end

  def logout
    @driver.find_element(
        :css,
        'form[action="?page=login&action=logout"] input[type="submit"]'
    ).click
  end

  def strftime(t = nil)
    t ||= @new_date
    t.strftime('%Y-%m-%d')
  end

  def get_expiration
    @driver.find_element(:css, '#content form table tr:nth-child(2) td:nth-child(2)').text
  end

  def set_expiration(date = nil)
    @driver.find_element(
        :css,
        '#content form input[name="paid_until"]'
    ).send_keys(strftime(date))
    submit
  end

  def submit
    @driver.find_element(:css, '#content form table input[type="submit"]').click
  end

  it 'sets exact date' do
    @new_date = Date.today >> 3  # now + 3 months
    set_expiration

    expect(get_expiration).to eq(strftime)
  end

  it 'adds n months to last paid date' do
    @new_date = Date.today
    set_expiration

    @new_date = @new_date >> 2  # +2 months
    @driver.find_element(
        :css,
        '#content form input[name="months_to_add"]'
    ).send_keys('2')
    submit

    expect(get_expiration).to eq(strftime)
  end

  it 'adds n months from now' do
    @new_date = Date.today >> 5  # now + 5 months
    @driver.find_element(
        :css,
        '#content form input[name="months_to_add"]'
    ).send_keys('5')

    select = Selenium::WebDriver::Support::Select.new(
        @driver.find_element(
            :css,
            '#content form select[name="add_from"]'
        )
    )
    select.select_by(:value, 'from_now')
    submit

    expect(get_expiration).to eq(strftime)
  end
end
