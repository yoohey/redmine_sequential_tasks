# frozen_string_literal: true

module RedmineSequentialTasks
  # The name of the project menu tab and the heading of the plugin's project screens (plugin setting "tab_label").
  # Blank means the name in the locale files. Kept short so that a long entry does not stretch the menu.
  module TabLabel
    module_function

    MAX_LENGTH = 30

    def text
      custom = (Setting.plugin_redmine_sequential_tasks || {})['tab_label'].to_s.strip
      custom.empty? ? ::I18n.t('sequential_tasks.menu.project') : custom[0, MAX_LENGTH]
    end
  end
end
