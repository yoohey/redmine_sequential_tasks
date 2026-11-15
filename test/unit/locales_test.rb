# frozen_string_literal: true

# Standalone test (no Redmine test DB needed): ruby test/unit/locales_test.rb
# Rule under test (UI strings live in config/locales/ja.yml and en.yml, nothing is hard-coded)
require 'minitest/autorun'
require 'yaml'

class LocalesTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  CJK = /[　-〿぀-ヿ一-鿿＀-￯]/

  def flatten(hash, prefix = nil)
    hash.each_with_object({}) do |(key, value), out|
      path = [prefix, key].compact.join('.')
      value.is_a?(Hash) ? out.merge!(flatten(value, path)) : out[path] = value
    end
  end

  def load_locale(code)
    flatten(YAML.load_file(File.join(ROOT, "config/locales/#{code}.yml")).fetch(code))
  end

  def variables(text)
    text.scan(/%\{(\w+)\}/).flatten.sort
  end

  def test_ja_and_en_have_the_same_keys
    ja = load_locale('ja')
    en = load_locale('en')
    assert_empty ja.keys - en.keys, 'keys only in ja.yml'
    assert_empty en.keys - ja.keys, 'keys only in en.yml'
  end

  def test_no_translation_is_empty
    %w[ja en].each do |code|
      load_locale(code).each { |key, text| refute_empty text.to_s.strip, "#{code}: #{key} is empty" }
    end
  end

  def test_both_languages_use_the_same_interpolation_variables
    ja = load_locale('ja')
    en = load_locale('en')
    ja.each do |key, text|
      assert_equal variables(text), variables(en[key]), "interpolation variables differ for #{key}"
    end
  end

  def test_the_english_file_has_no_japanese_text
    load_locale('en').each { |key, text| refute_match CJK, text, "en: #{key} contains Japanese" }
  end

  def test_the_japanese_file_really_is_japanese_where_it_has_words
    ja = load_locale('ja')
    # a few anchors, so a copy-paste of the English file would be noticed
    assert_match CJK, ja['sequential_tasks.state.pending']
    assert_match CJK, ja['sequential_tasks.flash.no_changes']
  end

  # Source files must not hard-code Japanese outside of comments
  def test_no_hard_coded_japanese_in_the_source
    files = Dir[File.join(ROOT, 'init.rb'), File.join(ROOT, 'app/**/*.{rb,erb}'), File.join(ROOT, 'lib/**/*.rb'),
                File.join(ROOT, 'assets/**/*.{js,css}')]
    assert files.size > 10
    offenders = []
    files.each do |file|
      File.readlines(file, encoding: 'UTF-8').each_with_index do |line, i|
        next unless line =~ CJK
        stripped = line.strip
        next if stripped.start_with?('#', '<%#', '//', '/*', '*') || (stripped.start_with?('<!--') && stripped.end_with?('-->'))

        offenders << "#{file.sub("#{ROOT}/", '')}:#{i + 1}: #{stripped[0, 80]}"
      end
    end
    assert_empty offenders, "hard-coded Japanese (move it to config/locales):\n#{offenders.first(40).join("\n")}"
  end
end
