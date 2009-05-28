require 'activerecord'
require 'globalize/backend/static'

module Globalize
  module Backend
    class Database < Static
      
      # Loads all available translations from db and merge them into the already loaded translations
      def load_translations(*args)
        data = Translation.load_all_entries
        data.each { |locale, d| merge_translations(locale, d) }
      end
      
      # Stores translations for the given locale/key in the database.
      # if a deep nested hash is given it is flattened first
      def store_translations(locale, data)
        data = flatten data
        data.each { |key, data| store_translation(locale, key, data) }
      end
      
      # stores a single translation in the database and merges it directly into the memory collection
      def store_translation(locale, key, text, count=nil)
        if count.nil?
          data = text
        else 
          pluralization_index = pluralizer(locale).call(count)
          data = { pluralization_index => text }
        end
        Translation.create_or_update(locale, key, data)
        # merge the stored translation back to the memory collection 
        merge_translations(locale, { key => Translation.load_entry(locale, key) })
      end
      
      def available_locales
        Translation.find(:all, :select => "DISTINCT locale").map { |t| t.locale.to_sym }
      end
      
      def flat_translations
        flattened = {}
        translations.each{|locale, values|
          flattened[locale] = flatten values
        }
        flattened
      end
      
      protected
      
      # flattens a deep nested hash to use dotted keys for db storage
      # input => { 
      #         :scope => { 
      #           :foo => { :one => "one foo", :other => "other foo" }, 
      #           :bar => "a bar"
      #         },
      #         :global => "not scoped"
      #       }
      # result => {
      #  :"scope.foo"=>{:one=>"one foo", :other=>"other foo"},
      #  :global=>"not scoped",
      #  :"scope.bar"=>"a bar"}  
      def flatten(raw)
        flat = {}
        
        # anonymous function to be called internally
        flatter = proc do |hash, scope|
          hash.each{ |key, value|
            key = key.to_sym
            new_scope = scope.blank? ? key : [scope, key].join(".").to_sym
            if value.instance_of? Hash
              flatter.call(value, new_scope)
            else
              # if the key is a pluralisation index stop further scoping
              # FIXME the pluralisation keys depends on the language and should be variable...
              if [:zero, :one, :other, :few].include? key
                if flat[scope] 
                  flat[scope][key] = value
                else
                  flat[scope] = {key=>value}
                end 
              else
                flat[new_scope] = value
              end
            end
          }
        end
        
        flatter.call(raw, "")
        return flat
      end
      
      
      # returns a pluralized version of the entry
      # count defaults to 1
      def pluralize(locale, entry, count)
        
        # return the entry directly if it is a string
        return entry unless entry.is_a?(Hash)
        
        key = pluralizer(locale).call(count.nil? ? 1 : count)
        # fallback to other if :zero is not set
        key = :other if key == :zero && !entry.has_key?(:zero)
        
        # raise a pluralization error only if count is explicitely set and the entry is not available
        # else return the entry that may be a hash or the translated string
        if entry.has_key?(key)
          translation entry[key], :plural_key => key.to_s
        elsif count
          raise I18n::InvalidPluralizationData.new(entry, count)
        else
          translation entry, :plural_key => nil
        end
      end

      class Translation < ::ActiveRecord::Base
        set_table_name 'globalize_translations'
        
        validates_presence_of :locale, :key
        validates_uniqueness_of :key, :scope => [:locale, :pluralization_index]
        
        class << self
          
          #
          # creates or updates an entry.
          # data may be a string or a hash with pluralization indexes as keys
          #
          def create_or_update(locale, key, data)
            
            locale, key = locale.to_s, key.to_s
            
            # create/update all of the pluralization forms
            if data.is_a? Hash            
              data.each do |pluralization_index, text|
                if record = find_by_locale_and_key_and_pluralization_index(locale, key, pluralization_index)
                  record.update_attribute(:text, text)
                else
                  create :locale => locale, :key => key, :pluralization_index => pluralization_index.to_s, :text => text
                end
              end
            
            # create/update without pluralization
            else
              if record = find_by_locale_and_key_and_pluralization_index(locale, key, nil)
                record.update_attribute(:text, data)
              else
                create :locale => locale, :key => key, :text => data
              end
            end
            
          end
          
          # loads all translation data from database
          def load_all_entries
            results = self.all :order=>'`locale`, `key`'
            data = {}
            
            results.each do |result| 
              #create an empty hash for each locale initially
              data[result.locale] ||= {}
              
              # create the deep nested scopes from the dotted key
              scopes = result.key.split(".").map{|k| k.to_sym}
              key = scopes.pop
              scope = scopes.inject(data[result.locale]) do |scope, s| 
                scope[s] = {} unless scope[s]
                scope[s] 
              end
              
              # if we have a pluralization form and the translation key already exists add the specific pluralization form
              if scope[key] && result.pluralization_index
                scope[key][result.pluralization_index] = result.text
              
              # if we have a pluralization index add the initial hash  
              elsif result.pluralization_index
                scope[key] = { result.pluralization_index => result.text }
              
              # else we just add the simple text
              else 
                scope[key] = result.text
              end
          
            end
            return data
          end
          
          # loads a single entry from database
          # returns a simple string or a hash with pluralization indexes as keys
          def load_entry(locale, key)
            locale, key = locale.to_s, key.to_s
            data = self.find_all_by_locale_and_key(locale, key)
            result = {}
            data.each do |row|
              #only return the simple translation if one is set 
              return row.text unless row.pluralization_index
              result[row.pluralization_index.to_sym] = row.text
            end
            return result
          end
          
          
        end
      end
    end
  end
end
