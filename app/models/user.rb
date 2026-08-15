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
  has_many :budgets, through: :categories

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
  # the app would demand the entire bill out of the next paycheck.
  validates :period_anchor_date,
            presence: { message: "is required when you set a period" },
            if: :period_cadence

  validate :default_account_is_own_account

  # `prepend: true` is load-bearing: without it the `has_many :pools, dependent: :destroy`
  # callback runs first, hits the account pool while it still has children, and aborts.
  before_destroy :destroy_child_pools_first, prepend: true

  STRIDE_DAYS = { "weekly" => 7, "biweekly" => 14 }.freeze

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
