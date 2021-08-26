# frozen_string_literal: true

module Aurora
  module Inflector
    def titleize
      gsub(/\b(?<!\w['â`])[a-z]/, &:capitalize)
    end
  end
end
String.include(Aurora::Inflector)
