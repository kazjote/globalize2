module I18n
  class << self
    def chain_backends(*args)
      self.backend = Globalize::Backend::Chain.new(*args)
    end
  end
end
  
module Globalize  
  module Backend
    class Chain      
      def initialize(*args)
        add(*args) unless args.empty?
      end
      
      # Change this to a) accept any number of backends and b) accept classes.
      # When classes are passed instantiate them and add the instances as backends.
      # Return the added backends from #add.
      #
      # Add an initialize method that accepts the same arguments and passes them
      # to #add, so we could:
      #   I18n.backend = Globalize::Backend::Chain.new(Globalize::Backend::Foo, Globalize::Backend::Bar)
      #   Globalize::Backend::Chain.new(:foo, :bar)
      #   Globalize.chain_backends :foo, :bar
      def add(*backends)
        backends.each do |backend|
          backend = Globalize::Backend.const_get(backend.to_s.capitalize) if backend.is_a? Symbol
          backend = backend.new if backend.is_a? Class
          self.backends << backend
        end
      end
      
      def load_translations(*args)
        backends.each{|backend| backend.load_translations(*args) }
      end
    
      # For defaults:
      # Never pass any default option to the backends but instead implement our own default
      # mechanism (e.g. symbols as defaults would need to be passed to the whole chain to
      # be translated).
      #
      # For namespace lookup: 
      # Only return if the result is not a hash OR count is not present, otherwise merge them.
      # So in effect the count variable would control whether we have a namespace lookup or a 
      # pluralization going on.
      #
      # Exceptions:
      # Make sure that we catch MissingTranslationData exceptions and raise
      # one in the end when no translation was found at all.
      #
      # For bulk translation:
      # If the key is an array we need to call #translate for each of the
      # keys and collect the results.
      
      def translate(locale, key, options = {})
        raise I18n::InvalidLocale.new(locale) if locale.nil?
        return key.map{|k| translate locale, k, options } if key.is_a? Array
        default = options.delete(:default)
        
        result = backends.inject(nil) do |namespace, backend|
          begin
            translation = backend.translate(locale.to_sym, key, options)
            if namespace_lookup?(translation, options)
              namespace ||={}
              # deep_merge by Stefan Rusterholz, see http://www.ruby-forum.com/topic/142809
              merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
              translation.merge(namespace, &merger)
            elsif translation
              return translation 
            end
          rescue I18n::MissingTranslationData
            namespace
          end
        end
        
        result || default(locale, default, options) || raise(I18n::MissingTranslationData.new(locale, key, options))
      end
      
      # return the result from the first backend not throwing an error
      def localize(locale, object, format = :default)
        backends.each do |backend|
          result = backend.localize(locale, object, format) rescue nil and return result
        end
        #raise I18n::MissingTranslationData.new(locale, :"date.formats",{})
      end
      
      #
      # stores the translation in the first backend of the chain returning something for store_translations
      #
      def store_translations(locale, data)
        backends.each do |backend|
          result = backend.store_translations(locale, data) and return result
        end
      end
      
      def store_translation(locale, key, data, count=1)
        backends.each do |backend|
          backend.store_translation(locale, key, data, count) and return
        end
      end
        
      
      def reload!
        backends.each do |b|
          b.reload!
        end
      end
      
      def available_locales 
        a =[]
        backends.each do |b|
          a += b.available_locales
        end
        return a
      end
    
      protected
        def backends
          @backends ||= []
        end
        
        def default(locale, default, options = {})
          case default
            when String then default
            when Symbol then translate locale, default, options
            when Array  then default.each do |obj| 
              result = default(locale, obj, options.dup) and return result
            end and nil
          end
        rescue I18n::MissingTranslationData
          nil
        end
        
        def namespace_lookup?(result, options)
          result.is_a?(Hash) and not options.has_key?(:count)
        end
    end
  end
end