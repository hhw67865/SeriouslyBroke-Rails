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
  enum :pay_cadence, { weekly: 0, biweekly: 1, semimonthly: 2, monthly: 3 }, prefix: :pay

  normalizes :timezone, with: ->(value) { value.presence }

  validates :email, confirmation: { case_sensitive: false }, if: :will_save_change_to_email?
  validates :timezone,
            inclusion: { in: TZInfo::Timezone.all_identifiers },
            allow_nil: true

  validate :default_account_is_own_account

  STRIDE_DAYS = { "weekly" => 7, "biweekly" => 14 }.freeze

  def toggle_theme!
    update(theme: light? ? :dark : :light)
  end

  # Every pay date in [from, to], ascending. Empty unless a cadence is configured.
  def pay_dates(from:, to:)
    from = from.to_date
    to = to.to_date
    return [] if pay_cadence.blank? || pay_anchor_date.blank? || to < from

    case pay_cadence
    when "weekly", "biweekly" then strided_pay_dates(STRIDE_DAYS.fetch(pay_cadence), from, to)
    when "monthly" then monthly_pay_dates([pay_anchor_date.day], from, to)
    when "semimonthly" then monthly_pay_dates(semimonthly_days, from, to)
    else []
    end
  end

  private

  # The anchor is one occurrence of the series, not its start, so the schedule
  # extends backward from it as well — `ceil` handles a negative offset.
  def strided_pay_dates(stride, from, to)
    steps = ((from - pay_anchor_date).to_i / stride.to_f).ceil
    first = pay_anchor_date + (steps * stride)
    return [] if first > to

    (first..to).step(stride).to_a
  end

  def monthly_pay_dates(days, from, to)
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
    first = pay_anchor_date.day
    [first, first <= 15 ? first + 15 : first - 15].sort
  end

  def default_account_is_own_account
    return if default_account.blank?
    return if default_account.pool_type_account? && default_account.user_id == id

    errors.add(:default_account, "must be an account you own")
  end
end
