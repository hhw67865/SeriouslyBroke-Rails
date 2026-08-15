# frozen_string_literal: true

# Computes what a single funding rule needs from the next paycheck.
# See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §4.1-4.2
class BudgetCalculator
  attr_reader :budget, :today

  def initialize(budget, today: Date.current)
    @budget = budget
    @today = today
  end

  # `.to_d` is load-bearing. The `money` column casts to BigDecimal when it comes
  # back from Postgres, but an in-memory record assigned `amount: 180` keeps the
  # Integer — and `Integer / Integer` in #required truncates the cents (180/14 was
  # returning 12, not 12.86). A Float assignment is just as unwelcome in money math.
  def target = budget.amount.to_d

  # The cycle rolls when the bill is PAID, not when the date passes. Rolling on
  # the date alone would silently forget an obligation that was never settled.
  def due_date
    return period_end if budget.anchor_date.nil?
    return budget.anchor_date if budget.interval_months.nil?

    budget.anchor_date + (cycles_completed * budget.interval_months).months
  end

  def period_end
    budget.basis_per_paycheck? ? pay_period_end : today.end_of_month
  end

  def cycles_completed
    return elapsed_cycles if budget.item.nil?

    budget.item.entries.where(date: budget.anchor_date..).count
  end

  # How many occurrences of this bill have already come due, regardless of what
  # was recorded. Once today reaches the anchor, one occurrence has passed — so
  # this is (whole intervals elapsed) + 1, never a bare division.
  def elapsed_cycles
    return 0 if today < budget.anchor_date

    (months_since_anchor / budget.interval_months) + 1
  end

  def overdue?
    budget.item.present? && due_date < today
  end

  # `0.to_d` rather than a bare `0`: on the overfunded path `max` returns the
  # literal it was given, and an Integer leaking out here made #required's return
  # type depend on whether the rule happened to be funded.
  def shortfall(allocated)
    [target - allocated, 0.to_d].max
  end

  def periods_until_due
    [user.pay_dates(from: today, to: due_date).count, 1].max
  end

  def required(allocated)
    (shortfall(allocated) / periods_until_due).round(2)
  end

  private

  # Budget#user resolves in both category and pool mode, so this never nils out.
  def user = budget.user

  # Whole calendar months from the anchor to today, backing off one when today
  # has not yet reached the anchor's day of the month — Dec 1 is not yet a full
  # six months past a Jun 15 anchor, and counting it would roll the bill early.
  def months_since_anchor
    anchor = budget.anchor_date
    months = ((today.year * 12) + today.month) - ((anchor.year * 12) + anchor.month)
    today.day < anchor.day ? months - 1 : months
  end

  def pay_period_end
    next_payday = user.pay_dates(from: today + 1, to: today + 45).first
    next_payday ? next_payday - 1 : today.end_of_month
  end
end
