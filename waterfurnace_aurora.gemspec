require_relative "lib/aurora/version"

Gem::Specification.new do |s|
  s.name = 'waterfurnace_aurora'
  s.version = Aurora::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ["Cody Cutrer"]
  s.email = "cody@cutrer.com'"
  s.homepage = "https://github.com/ccutrer/waterfurnace"
  s.summary = "Library for communication with WaterFurnace Aurora control systems"
  s.license = "MIT"

  s.executables = ['aurora_mqtt_bridge']
  s.files = Dir["{bin,lib}/**/*"]

  s.add_dependency 'mqtt', "~> 0.5.0"
  s.add_dependency 'net-telnet-rfc2217', "~> 0.0.4"
  s.add_dependency 'ccutrer-serialport', "~> 1.0.0"
  s.add_dependency 'rmodbus-ccutrer', "~> 2.0"

  s.add_development_dependency 'byebug', "~> 9.0"
  s.add_development_dependency 'rake', "~> 13.0"
  s.add_development_dependency 'gserver', "~> 0.0.1"
end
