# before all
require 'bundler/setup'
require 'page-object'
require 'page-object/page_factory'
require 'watir-webdriver'
require 'yaml'

World(PageObject::PageFactory)

def browser(environment, test_name, saucelabs_username, saucelabs_key)
  if environment == :cloudbees
    sauce_browser(test_name, saucelabs_username, saucelabs_key)
  else
    local_browser
  end
end
def environment
  if ENV['ENVIRONMENT'] == 'cloudbees'
    :cloudbees
  else
    :local
  end
end
def local_browser
  if ENV['BROWSER_LABEL']
    browser_label = ENV['BROWSER_LABEL'].to_sym
  else
    browser_label = :firefox
  end

  Watir::Browser.new browser_label
end
def sauce_api(json, saucelabs_username, saucelabs_key)
  %x{curl -H 'Content-Type:text/json' -s -X PUT -d '#{json}' http://#{saucelabs_username}:#{saucelabs_key}@saucelabs.com/rest/v1/#{saucelabs_username}/jobs/#{$session_id}}
end
def sauce_browser(test_name, saucelabs_username, saucelabs_key)
  config = YAML.load_file('config/config.yml')
  browser_label = config[ENV['BROWSER_LABEL']]

  caps = Selenium::WebDriver::Remote::Capabilities.send(browser_label['name'])
  caps.platform = browser_label['platform']
  caps.version = browser_label['version']
  caps[:name] = "#{test_name} #{ENV['JOB_NAME']}##{ENV['BUILD_NUMBER']}"

  require 'selenium/webdriver/remote/http/persistent' # http_client
  browser = Watir::Browser.new(
    :remote,
    http_client: Selenium::WebDriver::Remote::Http::Persistent.new,
    url: "http://#{saucelabs_username}:#{saucelabs_key}@ondemand.saucelabs.com:80/wd/hub",
    desired_capabilities: caps)

  browser.wd.file_detector = lambda do |args|
    # args => ['/path/to/file']
    str = args.first.to_s
    str if File.exist?(str)
  end

  browser
end
def test_name(scenario)
  if scenario.respond_to? :feature
    "#{scenario.feature.name}: #{scenario.name}"
  elsif scenario.respond_to? :scenario_outline
    "#{scenario.scenario_outline.feature.name}: #{scenario.scenario_outline.name}: #{scenario.name}"
  end
end

config = YAML.load_file('config/config.yml')
mediawiki_username = config['mediawiki_username']

secret = YAML.load_file('/private/wmf/secret.yml')
mediawiki_password = secret['mediawiki_password']
saucelabs_username = secret['saucelabs_username']
saucelabs_key = secret['saucelabs_key']

does_not_exist_page_name = Random.new.rand

Before do |scenario|
  @config = config
  @does_not_exist_page_name = does_not_exist_page_name
  @mediawiki_username = mediawiki_username
  @mediawiki_password = mediawiki_password
  @browser = browser(environment, test_name(scenario), saucelabs_username, saucelabs_key)
  $session_id = @browser.driver.instance_variable_get(:@bridge).session_id
end

After do |scenario|
  if environment == :cloudbees
    sauce_api(%Q{{"passed": #{scenario.passed?}}}, saucelabs_username, saucelabs_key)
    sauce_api(%Q{{"public": true}}, saucelabs_username, saucelabs_key)
  end
  @browser.close
end
