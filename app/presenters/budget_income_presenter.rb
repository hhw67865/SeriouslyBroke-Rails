# frozen_string_literal: true

# The Your income page: the period declaration and which categories count toward typical income.
# `typed` is the posted cadence and anchor, if any; the measure is built off them, saved or not.
class BudgetIncomePresenter
  attr_reader :user, :category_ids

  def initialize(user:, typed: nil, category_ids: nil)
    @user = user
    @typed = typed
    @category_ids = category_ids
  end

  # What the form renders: the user as saved, or a probe carrying what was typed and its errors.
  def declaration = @typed.nil? ? user : probe

  def income_categories
    @income_categories ||= user.categories.incomes.order(:name).to_a
  end

  def checked?(category) = chosen.include?(category.id)

  def declared? = declaration.period_cadence.present?
  def cadence = declaration.period_cadence&.humanize
  def valid_period? = declaration.period_cadence.blank? || declaration.period_anchor_date.present?
  def history? = typical_income.present?
  def typical_income = measure.typical
  delegate :periods, to: :measure

  private

  def measure = @measure ||= IncomeMeasure.new(declaration, category_ids: chosen, today: user.today)

  def probe
    @probe ||= User.find(user.id).tap do |found|
      found.assign_attributes(@typed.to_h.symbolize_keys.slice(:period_cadence, :period_anchor_date))
      found.validate
    end
  end

  def chosen
    @chosen ||= category_ids.nil? ? user.categories.incomes.regular.ids : user.categories.incomes.where(id: category_ids).ids
  end
end
