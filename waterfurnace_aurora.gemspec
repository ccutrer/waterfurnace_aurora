# frozen_string_literal: true

require_relative "lib/aurora/version"

Gem::Specification.new do |s|
  s.name = "waterfurnace_aurora"
  s.version = Aurora::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ["Cody Cutrer"]
  s.email = "cody@cutrer.us'"
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

  s.add_dependency "ccutrer-serialport", "~> 1.0"
  s.add_dependency "mqtt-homie-homeassistant", "~> 1.0", ">= 1.0.6"
  s.add_dependency "net-telnet-rfc2217", "~> 1.0", ">= 1.0.1"
  s.add_dependency "puma", "~> 6.4"
  s.add_dependency "rackup", ">= 1.0.0", "< 3.0.a"
  s.add_dependency "rmodbus", "~> 2.1"
  s.add_dependency "sinatra", ">= 2.2.4", "< 5.0.a"
end
