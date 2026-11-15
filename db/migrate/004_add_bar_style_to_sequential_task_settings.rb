# frozen_string_literal: true

# The look of the stage bars is chosen per tracker. It used to be one plugin setting for
# everybody: that value is copied to every tracker that already has a setting.
class AddBarStyleToSequentialTaskSettings < ActiveRecord::Migration[7.2]
  def up
    add_column :sequential_task_settings, :bar_style, :string, null: false, default: 'bold'

    old = (Setting.plugin_redmine_sequential_tasks || {})['bar_style'].to_s
    execute("UPDATE sequential_task_settings SET bar_style = #{connection.quote(old)}") if %w[bold subtle light].include?(old)
  end

  def down
    remove_column :sequential_task_settings, :bar_style
  end
end
