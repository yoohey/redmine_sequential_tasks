# frozen_string_literal: true

module RedmineSequentialTasks
  # Dates are shown in the time zone of the current user (stored times are UTC).
  # "Today" is User.current.today, as in Redmine itself.
  module UserTime
    module_function

    # The calendar date of a stored time in the current user's time zone, or nil
    def date_of(time)
      return nil if time.nil?

      User.current.convert_time_to_user_timezone(time).to_date
    end
  end
end
