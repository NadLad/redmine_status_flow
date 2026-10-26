# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# A missing key does not fail a request: it renders "translation missing" to
# the user, or falls back to English, silently. These tests make the gap loud.
class LocalesTest < ActiveSupport::TestCase
  LOCALES = %w[en fr es tr zh].freeze
  LOCALE_DIR = File.expand_path('../../config/locales', __dir__)

  def self.load_locale(code)
    data = YAML.safe_load(File.read(File.join(LOCALE_DIR, "#{code}.yml")))
    flatten(data.fetch(code))
  end

  def self.flatten(hash, prefix = nil)
    hash.each_with_object({}) do |(key, value), acc|
      full = prefix ? "#{prefix}.#{key}" : key
      value.is_a?(Hash) ? acc.merge!(flatten(value, full)) : acc[full] = value
    end
  end

  REFERENCE = load_locale('en')

  test 'every locale ships exactly the keys English has' do
    LOCALES.each do |code|
      keys = self.class.load_locale(code)

      assert_empty REFERENCE.keys - keys.keys, "#{code}.yml is missing keys"
      assert_empty keys.keys - REFERENCE.keys, "#{code}.yml has keys English does not"
    end
  end

  # Keys owned by the plugin. Redmine core keys (l(:field_tracker),
  # l(:label_search)...) are deliberately excluded: they live in Redmine's own
  # locales, not here.
  OWN_PREFIXES = %w[label_status_flow_ label_history_ error_status_history_].freeze
  OWN_KEYS = %w[field_last_status_update permission_search_status_history].freeze

  def self.used_keys
    sources = Dir[File.expand_path('../../{app,lib}/**/*.{rb,erb}', __dir__)]
    keys = sources.flat_map { |file| File.read(file).scan(/\bl\(:(\w+)/).flatten }.uniq
    keys.select { |key| OWN_PREFIXES.any? { |p| key.start_with?(p) } || OWN_KEYS.include?(key) }
  end

  test 'every key the code asks for is defined in English' do
    used = self.class.used_keys

    assert_operator used.size, :>, 10, 'the scan found almost no keys, check the regex'
    # A pluralized key is nested in YAML (zero/one/other) and flattens to
    # "key.zero", so a bare key counts as defined when a child of it exists.
    missing = used.reject { |key| REFERENCE.key?(key) || REFERENCE.keys.any? { |k| k.start_with?("#{key}.") } }

    assert_empty missing, 'a key used in code is missing from en.yml'
  end

  test 'pluralized and interpolated keys render in every locale' do
    LOCALES.each do |code|
      I18n.with_locale(code) do
        [0, 1, 3].each do |count|
          text = I18n.t(:label_status_flow_change_count, count: count)
          refute_match(/translation missing/i, text)
          refute_match(/%\{/, text)
        end

        %i[label_status_flow_for_duration label_status_flow_duration_days
           label_status_flow_duration_hours label_status_flow_duration_minutes].each do |key|
          text = I18n.t(key, duration: 'X', days: 1, hours: 2, minutes: 3)
          refute_match(/translation missing/i, text)
          refute_match(/%\{/, text)
        end
      end
    end
  end
end
