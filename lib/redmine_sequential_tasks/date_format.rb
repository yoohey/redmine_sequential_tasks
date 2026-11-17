# frozen_string_literal: true

module RedmineSequentialTasks
  # How dates are written on the screens. A full date follows Redmine's "Date format" setting (Administration >
  # Settings > Display), or the language's default when it is blank, the same as Redmine's own format_date.
  # Redmine has no setting for a short month and day, so that one follows the language (ja "11/16", en "Nov 16").
  module DateFormat
    module_function

    def full_pattern
      Setting.date_format.presence || ::I18n.t('date.formats.default')
    end

    def short_pattern
      ::I18n.t('sequential_tasks.date.short')
    end

    def year_month_pattern
      ::I18n.t('sequential_tasks.date.year_month')
    end

    def full(date)
      date && ::I18n.l(date.to_date, format: full_pattern)
    end

    def short(date)
      date && ::I18n.l(date.to_date, format: short_pattern)
    end

    def year_month(date)
      date && ::I18n.l(date.to_date, format: year_month_pattern)
    end

    # For the screens' scripts (SqDates): the same patterns and the month names they may use
    def data_attributes
      { 'data-sq-date-short' => short_pattern, 'data-sq-date-full' => full_pattern,
        'data-sq-months' => Array(::I18n.t('date.abbr_month_names')).drop(1).to_json }
    end
  end
end
