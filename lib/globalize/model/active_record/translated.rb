module Globalize
  module Model
  
    class MigrationError < StandardError; end
    class UntranslatedMigrationField < MigrationError; end
    class MigrationMissingTranslatedField < MigrationError; end
    class BadMigrationFieldType < MigrationError; end
  
    module ActiveRecord
      module Translated
        def self.included(base)
          base.extend ActMethods
        end

        module ActMethods
          def translates(*attr_names)
            options = attr_names.extract_options!
            options[:translated_attributes] = attr_names

            # Only set up once per class
            unless included_modules.include? InstanceMethods
              class_inheritable_accessor :globalize_options, :globalize_proxy
              
              include InstanceMethods
              extend  ClassMethods
              
              class << self
                alias_method_chain :find, :translations
                alias_method :all_attributes_exists_without_translations?, :all_attributes_exists?
                alias_method :all_attributes_exists?, :all_attributes_exists_with_translations?
                
              end
              
              self.globalize_proxy = Globalize::Model::ActiveRecord.create_proxy_class(self)
              has_many(
                :globalize_translations,
                :class_name   => globalize_proxy.name,
                :extend       => Extensions,
                :dependent    => :delete_all,
                :foreign_key  => class_name.foreign_key
              )

              after_save :update_globalize_record              
            end

            self.globalize_options = options
            Globalize::Model::ActiveRecord.define_accessors(self, attr_names)
            
            # Import any callbacks that have been defined by extensions to Globalize2
            # and run them.
            extend Callbacks
            Callbacks.instance_methods.each {|cb| send cb }
          end

          def locale=(locale)
            @@locale = locale
          end
          
          def locale
            (defined?(@@locale) && @@locale) || I18n.locale
          end          
        end

        # Dummy Callbacks module. Extensions to Globalize2 can insert methods into here
        # and they'll be called at the end of the translates class method.
        module Callbacks
        end
        
        # Extension to the has_many :globalize_translations association
        module Extensions
          def by_locales(locales)
            find :all, :conditions => { :locale => locales.map(&:to_s) }
          end
        end
        
        module ClassMethods          
          
          #
          # This method hooks before the AR finder.
          # If conditions with translated attributes are given:
          # => Join translation table
          # => Rewrite conditions accordingly
          # 
          def find_with_translations(*args)
            options = args.extract_options!
            
            if ( !translation_in_table? && options && options[:conditions] && options[:conditions].is_a?(Hash))
              translated_conditions = {}
              
              options[:conditions].delete_if {|key, value| 
                if globalize_options[:translated_attributes].include?(key.to_sym)
                   translated_conditions[i18n_attr(key)] = value
                   true
                end
              }
              
              unless translated_conditions.empty?
                options[:joins] = ((options[:joins]).to_a) << :globalize_translations
                sql = sanitize_sql_hash_for_conditions(options[:conditions].merge(translated_conditions))
                sql += " AND #{i18n_attr('locale')} IN (?)"
                conditions = [sql, I18n.fallbacks[I18n.locale].map{|tag| tag.to_s} ]
                options[:conditions] = conditions
              end
            end
            newargs = args.push(options)
            return find_without_translations(*newargs)
          end
          
          # 
          # This method hooks before the AR all_attributes_exists? method
          # globalized attributes are removed from the check. 
          # So they seem to be existing for the object even if just existing in the associated translation
          # 
          def all_attributes_exists_with_translations?(attribute_names)
            attribute_names = attribute_names.to_a.map( &:to_sym) - globalize_options[:translated_attributes]
            return all_attributes_exists_without_translations?(attribute_names)
          end
          
                    
          def create_translation_table!(fields)
            translated_fields = self.globalize_options[:translated_attributes]
            translated_fields.each do |f|
              raise MigrationMissingTranslatedField, "Missing translated field #{f}" unless fields[f]
            end
            fields.each do |name, type|
              unless translated_fields.member? name 
                raise UntranslatedMigrationField, "Can't migrate untranslated field: #{name}"
              end              
              unless [ :string, :text ].member? type
                raise BadMigrationFieldType, "Bad field type for #{name}, should be :string or :text"
              end 
            end
            translation_table_name = self.name.underscore + '_translations'
            self.connection.create_table(translation_table_name) do |t|
              t.references self.table_name.singularize
              t.string :locale
              fields.each do |name, type|
                t.column name, type
              end
              t.timestamps              
            end
          end

          def drop_translation_table!
            translation_table_name = self.name.underscore + '_translations'
            self.connection.drop_table translation_table_name
          end
          
          def translation_in_table?
            #I18n.locale == I18n.default_locale
            false 
          end
          
          private
          
          def i18n_attr(attribute_name)
            self.base_class.name.underscore + "_translations.#{attribute_name}"
          end
                    
        end
        
        module InstanceMethods
          def reload(options = nil)
            globalize.clear
            
            # clear all globalized attributes
            # TODO what's the best way to handle this?
            self.class.globalize_options[:translated_attributes].each do |attr|
              @attributes.delete attr.to_s
            end
            
            super options
          end
          
          def globalize
            @globalize ||= Adapter.new self
          end
          
          def update_globalize_record
            globalize.update_translations!
          end
          
          def translated_locales
            globalize_translations.scoped(:select => 'DISTINCT locale').map {|gt| gt.locale.to_sym }
          end
          
          # creates or updates associated translations
          
          def set_translations options
            options.keys.each do |key|

              translation = globalize_translations.find_by_locale(key.to_s) ||
                globalize_translations.build(:locale => key.to_s)
              translation.update_attributes!(options[key])
            end
          end
          
        end
      end
    end
  end
end