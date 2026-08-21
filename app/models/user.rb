# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable

  has_many :categories, dependent: :destroy
  has_many :pools, dependent: :destroy
  has_many :items, through: :categories
  has_many :entries, through: :items

  # THE SUGGESTIONS THIS USER HAS PUT DOWN (Henry's ruling of 2026-08-20). Owned by the user
  # directly rather than reached through the subject, because a dismissal is a fact about who is
  # reading the panel and not about the item, category or rule it names — the same subject can be
  # hidden by one user and showing for another, which is what `SuggestionEngine`'s lookup pins.
  #
  # `dependent: :destroy` for the ordinary reason, and note the SUBJECT side needs no counterpart:
  # a dismissal whose subject is deleted stops matching any suggestion the engine can derive, so it
  # is inert rather than dangling.
  has_many :suggestion_dismissals, dependent: :destroy

  belongs_to :default_account, class_name: "Pool", optional: true

  enum :theme, { light: 0, dark: 1 }

  # Prefixed so the enum never generates a bare `User#weekly?`, which would be
  # meaningless on a user.
  enum :period_cadence, { weekly: 0, biweekly: 1, semimonthly: 2, monthly: 3 }, prefix: :period

  normalizes :timezone, with: ->(value) { value.presence }

  validates :email, confirmation: { case_sensitive: false }, if: :will_save_change_to_email?
  validates :timezone,
            inclusion: { in: TZInfo::Timezone.all_identifiers },
            allow_nil: true
  validates :typical_income, numericality: { greater_than: 0 }, allow_nil: true
  # Without an anchor a configured cadence yields no boundaries at all, and the
  # `[count, 1].max` clamp downstream then reports "1 period before this bill" —
  # the app would demand the entire bill out of the next period.
  validates :period_anchor_date,
            presence: { message: "is required when you set a period" },
            if: :period_cadence

  validate :default_account_is_own_account

  # `prepend: true` is load-bearing: without it the `has_many :pools, dependent: :destroy`
  # callback runs first, hits the account pool while it still has children, and aborts.
  before_destroy :destroy_child_pools_first, prepend: true

  STRIDE_DAYS = { "weekly" => 7, "biweekly" => 14 }.freeze

  # How far #period_containing looks either side of a date to find the boundaries around it.
  # The longest cadence is monthly, so no period can exceed 31 days; 45 is the same window
  # BudgetCalculator#boundary_period_end already searches, kept identical so the two cannot
  # disagree about which boundary comes next.
  PERIOD_WINDOW_DAYS = 45

  # HOW MANY PERIODS A YEAR HOLDS, per cadence. The one divisor that turns a rule stated in
  # calendar time (a monthly cap, a six-monthly premium) into what it claims from one period.
  #
  # Semimonthly is 24 and not 26: it is twice a month, so it lands on the same two days of every
  # month and the year holds 24 of them. Biweekly is 26 — every fourteen days, which overruns
  # twice a month twice a year. Confusing the two is a 8% error in every normalised figure.
  PERIODS_PER_YEAR = { "weekly" => 52, "biweekly" => 26, "semimonthly" => 24, "monthly" => 12 }.freeze

  # 12 FOR A USER WHO HAS DECLARED NO CADENCE — i.e. the period IS the calendar month until they
  # say otherwise. Not zero and never a raise: `Budget#steady_ask` is asked about undeclared
  # users (the drift detector reads it, and the structural check computes before it renders), and
  # a divisor of zero there would 500 a page whose whole purpose is to let the user declare.
  #
  # The choice matches what the rest of the app already does with an undeclared period:
  # `BudgetCalculator#period_end` falls back to `today.end_of_month` and `User#period_containing`
  # to the calendar month. A monthly-basis rule therefore passes through unchanged, and a
  # per-period rule never consults this at all — `steady_ask` returns its amount directly.
  def periods_per_year = PERIODS_PER_YEAR.fetch(period_cadence, 12)

  # EVERY funding rule this user owns. There used to be two readers — `has_many :budgets, through:
  # :categories` reached the category-mode caps and this one reached both modes — and the pair is
  # collapsed to this one now that a rule is owned by a pool, full stop. The association is deleted
  # rather than left pointing at a link that can no longer be set (`budgets.category_id` is nil on
  # every row and nothing writes it), because a relation that always returns empty is a reader
  # waiting to be believed.
  #
  # Delegating to Budget.for_user rather than spelling the scope again: one place decides what
  # "a user's rules" means, so a screen and the controller lookup guarding it cannot disagree
  # about which rules exist.
  def all_budgets = Budget.for_user(self)

  def toggle_theme!
    update(theme: light? ? :dark : :light)
  end

  # Every period boundary in [from, to], ascending. Empty unless a period is configured.
  # A period is DECLARED by the user — it is not inferred from income, so multiple jobs
  # and irregular pay are simply not a question here.
  def period_boundaries(from:, to:)
    from = from.to_date
    to = to.to_date
    return [] if period_cadence.blank? || period_anchor_date.blank? || to < from

    case period_cadence
    when "weekly", "biweekly" then strided_dates(STRIDE_DAYS.fetch(period_cadence), from, to)
    when "monthly" then monthly_dates([period_anchor_date.day], from, to)
    when "semimonthly" then monthly_dates(semimonthly_days, from, to)
    else []
    end
  end

  # The whole period `date` falls in, as an inclusive Date range: from the boundary that
  # opened it through the day before the next one. A period is a RANGE, and the one caller
  # that needs it — replacing a period's distribution — must not reach for a bare date
  # equality, or a re-run two days later would leave the first split in place and add a
  # second on top of it.
  #
  # A user who declared no period has no boundaries at all, so the calendar month stands in.
  # That is the same fallback BudgetCalculator#period_end uses for a monthly rule, chosen so
  # the two answers agree rather than because a month is a period.
  def period_containing(date)
    date = date.to_date
    opened_on = period_boundaries(from: date - PERIOD_WINDOW_DAYS, to: date).last
    next_boundary = period_boundaries(from: date + 1, to: date + PERIOD_WINDOW_DAYS).first

    (opened_on || date.beginning_of_month)..(next_boundary ? next_boundary - 1 : date.end_of_month)
  end

  # The same period as a range of TIMESTAMPS, for querying the two columns that are
  # datetimes rather than dates: `pool_movements.date` and `entries.date`. Bounded by the
  # dates alone the last day would end at its own midnight, so a movement written at noon on
  # the closing day falls outside its own period — AllocationCommitter needed that to replace
  # a split it wrote hours earlier, and DistributionPresenter needs it to count a paycheck
  # deposited on the same day. One widening, in one place, because the two queries have to
  # agree about where the period ends or the screen and the write path describe different
  # periods.
  def period_datetimes_containing(date)
    range = period_containing(date)

    range.first.beginning_of_day..range.last.end_of_day
  end

  private

  # The anchor is one occurrence of the series, not its start, so the schedule
  # extends backward from it as well — `ceil` handles a negative offset.
  def strided_dates(stride, from, to)
    steps = ((from - period_anchor_date).to_i / stride.to_f).ceil
    first = period_anchor_date + (steps * stride)
    return [] if first > to

    (first..to).step(stride).to_a
  end

  def monthly_dates(days, from, to)
    dates = []
    cursor = from.beginning_of_month
    while cursor <= to
      days.each do |day|
        date = cursor.change(day: [day, cursor.end_of_month.day].min)
        dates << date if date.between?(from, to)
      end
      cursor = cursor.next_month
    end
    dates.sort
  end

  def semimonthly_days
    first = period_anchor_date.day
    [first, first <= 15 ? first + 15 : first - 15].sort
  end

  # Account pools use restrict_with_error so a user cannot delete an account that
  # still holds envelopes. That protection must not block deleting the whole user,
  # so child pools go first and no account is left holding anything.
  def destroy_child_pools_first
    pools.where.not(account_id: nil).destroy_all
  end

  # Records, not ids: on an unsaved user holding an unsaved pool both ids are nil, and
  # `nil == nil` accepted an account belonging to nobody.
  def default_account_is_own_account
    return if default_account.blank?
    return if default_account.pool_type_account? && default_account.user == self

    errors.add(:default_account, "must be an account you own")
  end
end
