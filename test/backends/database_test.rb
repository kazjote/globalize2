require File.join( File.dirname(__FILE__), '..', 'test_helper' )
require 'globalize/backend/database'
require 'globalize/translation'

class DatabaseTest < ActiveSupport::TestCase
  def setup
    reset_db! File.expand_path(File.join(File.dirname(__FILE__), '..', 'data', 'schema.rb'))
    I18n.backend = Globalize::Backend::Database.new
    translations = { :en => { :foo => "Foo", :scoped=>{:hi=>"hello", :bla=>"blubber"} },
      :cz => { :bar => { :one => "one cz bar", :few => "few cz bar", :other => "other cz bar" } } }

    translations.each do |locale, data|
      I18n.backend.store_translations locale, data
    end
  end

  test "available locales" do
    assert_equal [], ([:en, :cz]-I18n.available_locales)
  end

  test "should return a whole scope" do
    assert_equal({:hi=>"hello", :bla=>"blubber"}, I18n.translate(:scoped))
  end

  test "should store a single translation without a pluralization index" do
    assert_equal "translation missing: en-US, world", I18n.translate(:world)
    I18n.backend.store_translation :en, :world, "World"
    assert_equal "World", I18n.translate(:world)
  end

  test "should store single translations with pluralization indexes" do
    assert_equal "translation missing: en-US, girl", I18n.translate(:girl)
    I18n.backend.store_translation :en, :girl, "One girl", 1
    I18n.backend.store_translation :en, :girl, "Many girls", 5
    assert_equal "One girl", I18n.translate(:girl)
    assert_equal "One girl", I18n.translate(:girl, :count=>1)
    assert_equal "Many girls", I18n.translate(:girl, :count=>5)
  end

  test "should create translations" do
    I18n.backend.store_translations :en, { :hello => "Hello" }
    assert_equal "Hello", I18n.translate(:hello)
  end

  test "should create pluralized translations" do
    I18n.backend.store_translations :en, { :bar => { :one => "one bar", :other => "other bar" } }
    assert_equal "one bar",   I18n.translate(:bar)
    assert_equal "one bar",   I18n.translate(:bar, :count => 1)
    assert_equal "other bar", I18n.translate(:bar, :count => 2)
  end

  test "returns custom pluralized results" do
    with_locale :cz do
      assert_equal "one cz bar",   I18n.translate(:bar)
      assert_equal "one cz bar",   I18n.translate(:bar, :count => 1)
      assert_equal "few cz bar",   I18n.translate(:bar, :count => 3)
      assert_equal "other cz bar", I18n.translate(:bar, :count => 5)
    end
  end

  test "should update translations" do
    I18n.backend.store_translations :en, { :foo => "Foo!" }
    assert_equal "Foo!", I18n.translate(:foo)
  end

  test "should update translation" do
    I18n.backend.store_translation :en, :home, "home"
    assert_equal "home", I18n.translate(:home)
    I18n.backend.store_translation :en, :home, "home!!"
    assert_equal "home!!", I18n.translate(:home)
  end

  test "should update scoped translation" do
    I18n.backend.store_translation :en, :"scoped.home", "home"
    assert_equal "home", I18n.translate(:home, :scope => :scoped)
    I18n.backend.store_translation :en, :"scoped.home", "home!!"
    assert_equal "home!!", I18n.translate(:home, :scope => :scoped)
  end

  test "returns an instance of Translation::Static" do
    translation = I18n.translate :foo
    assert_instance_of Globalize::Translation::Static, translation
  end

  test "returns error message for missing translation" do
    message = I18n.translate :foz
    assert_equal "translation missing: en-US, foz", message
  end

  test "raise exception on missing translation" do
    assert_raise I18n::MissingTranslationData do
      I18n.translate :foz, :raise => true
    end
  end

  test "return flattened translations" do
    flattened = I18n.backend.flat_translations
    assert_equal(
      {:cz=>{:bar=>{:few=>"few cz bar", :one=>"one cz bar", :other=>"other cz bar"}},
       :en=>{:"scoped.hi"=>"hello", :"scoped.bla"=>"blubber", :foo=>"Foo"}}, flattened)
  end

  private
    def with_locale(locale, &block)
      begin
        old_locale, I18n.locale = I18n.locale, locale
        pluralizer = "#{locale}_pluralizer"
        I18n.backend.add_pluralizer(locale, send(pluralizer)) if respond_to? pluralizer
        yield
      rescue Exception
      ensure
        I18n.locale = old_locale
      end
    end

    def cz_pluralizer
      lambda{|c| c == 1 ? :one : (2..4).include?(c) ? :few : :other }
    end
end

