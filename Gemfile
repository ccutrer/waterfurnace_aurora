# frozen_string_literal: true

source "https://rubygems.org"

gemspec

if RUBY_VERSION >= "2.7"
  # these gems are not compatible with Ruby 2.5/2.6
  gem "debug", "~> 1.9", require: false, platform: :mri
  gem "rubocop-inst", "~> 1.0"
  gem "rubocop-rake", "~> 0.6"
end
