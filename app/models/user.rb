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

  STRIDE_DAYS = { "weekly" => 7, "biweekly" => 14 }.freeze

  # How far #period_containing looks either side of a date to find the boundaries around it.
  # The longest cadence is monthly, so no period can exceed 31 days; 45 is the window
  # BudgetCalculator#boundary_period_end searched, kept when that class was deleted because the
  # bound is a fact about the cadences rather than about the caller.
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
  # `#period_containing` below falls back to the calendar month, as `BudgetCalculator#period_end`
  # did before it was deleted. A monthly-basis rule therefore passes through unchanged, and a
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

  # THE CALENDAR DAY AN INSTANT FELL ON, IN THIS USER'S ZONE — the Ruby half of
  # `CategoryLedger::ENTRY_LOCAL_DAY`'s `AT TIME ZONE 'UTC' AT TIME ZONE COALESCE(…, 'UTC')`, and the
  # ONE spelling of it. `entries.date` and `adjustments.date` are both datetimes, so a Tokyo user's
  # Sep 12 is stored as Sep 11 15:00 UTC and `.to_date` under an ambient UTC zone (a job, a console,
  # a spec outside a request) answers Sep 11 while the SQL answers Sep 12. Re-zoning from the USER
  # rather than from `Time.zone` is what makes the two agree wherever this runs.
  #
  # IT LIVES ON THE USER because that is where the timezone lives and because three callers need it:
  # `Category#local_day` (the funded-since comparison), `Adjustment#local_day` (which period a delta
  # lands in) and `ClaimCalculator` (which period a spend lands in). It was `Category`'s private
  # method until the claims work gave it a second and a third caller.
  #
  # A DATE PASSES THROUGH UNTOUCHED, and the `DateTime` exclusion is load-bearing: `DateTime < Date`
  # in Ruby, so a plain `is_a?(Date)` test would let a real instant skip the conversion. A Date has
  # no instant to re-zone — `Date#in_time_zone` would invent midnight and shift the day.
  def local_day(moment)
    return moment if moment.is_a?(Date) && !moment.is_a?(DateTime)

    moment.in_time_zone(timezone.presence || "UTC").to_date
  end

  # ** THE DAY IT IS FOR THIS OWNER — the app's ONE spelling of "today", and the day every claim is
  # read against (computed-claims Task 3, fix round 2 — LOW-1). **
  #
  # It is `#local_day` asked of the one instant nobody stored. Fix round 1 made
  # `ClaimCalculator#overdue?` the DATE alone (`next_due_on < today`), which promoted `today` from a
  # window bound to the sole trigger of a trouble row — so the difference between UTC's day and the
  # owner's is now the difference between a bill that says `overdue · was Sep 2` and one that says
  # nothing.
  #
  # WHY NOT `Date.current`. That reader takes its zone from the AMBIENT `Time.zone`, and `config.time_zone`
  # is unset, so it is UTC's day by default. Inside a request the two agree — `ApplicationController`'s
  # `around_action :use_user_timezone` sets `Time.zone` to this user's for the whole action, and
  # `spec/requests/home_spec.rb`'s two owners pin that they agree there. What `Date.current` cannot do
  # is answer for a user OUTSIDE a request: a job, a console, a seed, a rake task, or a presenter built
  # in a spec gets whatever zone is ambient and reads UTC's day about a user in Tokyo. Taking the zone
  # from the USER is what makes every reader in the claims stack — this, `#local_day`,
  # `Adjustment#local_day`, `ClaimCalculator#rule_born_on` and `CategoryLedger::ENTRY_LOCAL_DAY`'s SQL —
  # answer the same day wherever it runs, which is the same argument `#local_day` above is here for.
  #
  # `Category#today` and `Budget#today` reach this through their own owner and are the only two other
  # spellings; nothing else in `app/` derives a day from the clock.
  def today = local_day(Time.current)

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
  # That was BudgetCalculator#period_end's fallback for a monthly rule too, chosen so the two
  # answers agreed rather than because a month is a period; that class is gone and this is now the
  # only answer.
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

  # Records, not ids: on an unsaved user holding an unsaved pool both ids are nil, and
  # `nil == nil` accepted an account belonging to nobody.
  def default_account_is_own_account
    return if default_account.blank?
    return if default_account.pool_type_account? && default_account.user == self

    errors.add(:default_account, "must be an account you own")
  end
end
