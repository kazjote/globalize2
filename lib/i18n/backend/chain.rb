module I18n
  module Backend
    class Chain # < Simple extend this to get the default method from the Simple backend?
      
      # Change this to a) accept any number of backends and b) accept classes.
      # When classes are passed instantiate them and add the instances as backends.
      # Return the added backends from #add.
      #
      # Add an initialize method that accepts the same arguments and passes them
      # to #add, so we could:
      #   I18n.backend = I18n::Backend::Chain.new(I18n::Backend::Spec, I18n::Backend::Simple)
      def add(backend)
        backends << backend
      end
    
      def translate(locale, key, options = {})
        # For bulk translation:
        # If the key is an array we need to call #translate for each of the
        # keys and collect the results.
        #
        # Exceptions:
        # Make sure that we catch MissingTranslationData exceptions and raise
        # one in the end when no translation was found at all.
        backends.inject({}) do |result, backend|
          # For defaults:
          # Never pass any default option to the backends but instead implement our own default
          # mechanism (e.g. symbols as defaults would need to be passed to the whole chain to
          # be translated).
          #
          # For namespace lookup: 
          # Only return if the result is not a hash OR count is not present, otherwise merge them.
          # So in effect the count variable would control whether we have a namespace lookup or a 
          # pluralization going on.
          begin
            translation = backend.translate(locale, key, options) 
            if namespace_lookup?(translation, options)
              result.merge! translation
            elsif translation
              return translation 
            end
          rescue I18n::MissingTranslationData
          end
          result
        end
      end
    
      protected
        def backends
          @backends ||= []
        end
        
        def namespace_lookup?(result, options)
          result.is_a?(Hash) and not options.has_key?(:count)
        end
    end
  end
end