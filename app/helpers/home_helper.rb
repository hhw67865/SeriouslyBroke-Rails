# frozen_string_literal: true

# The row vocabulary of Home's bands. See the UI design spec §4.4.
#
# HomeHelper rather than ApplicationHelper (which the brief suggested) for two reasons: it
# is the helper Rails always mixes into home views whatever `include_all_helpers` is set to,
# which was the brief's whole objection to PoolsHelper; and ApplicationHelper is already at
# rubocop's Metrics/ModuleLength limit, so this vocabulary does not fit there without
# starting to delete other people's comments.
module HomeHelper
  # `strftime("%b %-d")` rather than `l(date, format: :short)`: no view in this app formats
  # a date through I18n, and the locale's :short renders "Mar 01" where the spec's row
  # vocabulary reads "Mar 1". Same format string as WeeklyCalendarPresenter#range_label.
  def pool_status_label(status)
    case status.state
    when :overdrawn then "overdrawn #{number_to_currency(status.amount)}"
    when :overdue then "overdue · was #{status.due_on.strftime("%b %-d")}"
    when :wont_make_it then "won't make it · #{status.due_on.strftime("%b %-d")}"
    when :behind then "behind #{number_to_currency(status.amount)}"
    when :left_to_spend then "#{number_to_currency(status.amount)} left"
    else "#{number_to_currency(status.amount)} · on track"
    end
  end

  # A row on Home's attention list can be in trouble for a reason PoolStatus does not model:
  # the pool belongs to no account, so no account's money can reach it. That is a setup
  # problem, not a funding one (HomePresenter#fill_waterfall says why it is not a shortfall),
  # and a pool can be both unassigned and overdrawn — so the status is still said when it
  # has one.
  def pool_problem_label(status, orphan: false)
    return pool_status_label(status) unless orphan
    return "no account · #{pool_status_label(status)}" if status.needs_attention?

    "no account — nothing can fund it"
  end
end
