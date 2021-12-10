# frozen_string_literal: true

require_relative "lib/aurora/version"

Gem::Specification.new do |s|
  s.name = "waterfurnace_aurora"
  s.version = Aurora::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ["Cody Cutrer"]
  s.email = "cody@cutrer.com'"
  s.homepage = "https://github.com/ccutrer/waterfurnace_aurora"
  s.summary = "Library for communication with WaterFurnace Aurora control systems"
  s.license = "MIT"
  s.metadata = {
    "rubygems_mfa_required" => "true"
  }

  s.bindir = "exe"
  s.executables = Dir["exe/*"].map { |f| File.basename(f) }
  s.files = Dir["{exe,lib}/**/*"]

  s.required_ruby_version = ">= 2.5"

  s.add_dependency "ccutrer-serialport", "~> 1.0.0"
  s.add_dependency "mqtt-homeassistant", "~> 0.1", ">= 0.1.2"
  s.add_dependency "net-telnet-rfc2217", "~> 1.0", ">= 1.0.1"
  s.add_dependency "rmodbus-ccutrer", "~> 2.1"
  s.add_dependency "sinatra", "~> 2.1"

  s.add_development_dependency "byebug", "~> 11.0"
  s.add_development_dependency "rubocop", "~> 1.23"
  s.add_development_dependency "rubocop-performance", "~> 1.12"
  s.add_development_dependency "rubocop-rake", "~> 0.6"
end
