# frozen_string_literal: true

require "waterfurnace_aurora"
require "yaml"

module FixtureHelpers
  def fixture(name)
    YAML.safe_load_file(File.join(__dir__, "fixtures", "#{name}.yml"))
  end
end

RSpec.configure do |config|
  config.include FixtureHelpers
  config.order = :random
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
