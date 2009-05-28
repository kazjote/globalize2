require 'i18n/backend/simple'

module Globalize
  module Backend
    class Pluralizing < I18n::Backend::Simple
      
      def pluralize(locale, entry, count)
        return entry unless entry.is_a?(Hash) and count
        key = pluralizer(locale).call(count)
        # use other as fallback for zero if zero entry is not available
        key = :other if key == :zero && !entry.has_key?(:zero)
        raise I18n::InvalidPluralizationData.new(entry, count) unless entry.has_key?(key)
        translation entry[key], :plural_key => key
      end

      def add_pluralizer(locale, pluralizer)
        pluralizers[locale.to_sym] = pluralizer
      end

      def pluralizer(locale)
        pluralizers[locale.to_sym] || default_pluralizer
      end
      
      protected
        def default_pluralizer
          pluralizers[:en]
        end

        def pluralizers
          @pluralizers ||= { :en => lambda{|n| n == 1 ? :one : ( n == 0 ? :zero : :other) } }
        end

        # Overwrite this method to return something other than a String
        def translation(string, attributes)
          string
        end
    end
  end
end