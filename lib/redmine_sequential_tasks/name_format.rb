# frozen_string_literal: true

module RedmineSequentialTasks
  # How the names of assignees are written on the timeline and the matrix (plugin setting "name_order"):
  #   redmine    - follow Redmine's own user format (Administration > Settings > Display)
  #   first_last - "First Family"
  #   last_first - "Family First"
  # Groups keep their name. The order can be read once and passed in, for loops over many rows.
  module NameFormat
    ORDERS = %w[redmine first_last last_first].freeze

    module_function

    def order
      value = (Setting.plugin_redmine_sequential_tasks || {})['name_order'].to_s
      ORDERS.include?(value) ? value : 'redmine'
    end

    def name(principal, order = self.order)
      return nil if principal.nil?
      return principal.name unless principal.is_a?(User) && !principal.anonymous?

      case order
      when 'first_last' then [principal.firstname, principal.lastname].reject(&:blank?).join(' ')
      when 'last_first' then [principal.lastname, principal.firstname].reject(&:blank?).join(' ')
      else principal.name
      end
    end
  end
end
