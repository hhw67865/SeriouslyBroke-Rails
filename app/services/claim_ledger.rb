# frozen_string_literal: true

# Every rule's calculator for one user, fed in a fixed number of queries: the lanes' spending
# since the earliest window, and every adjustment in it.
class ClaimLedger
  class UnknownRule < StandardError; end

  attr_reader :user, :today

  def initialize(user, today: user.today)
    @user = user
    @today = today
  end

  def rules
    @rules ||= user.rules.includes(:item, category: :user).to_a
  end

  def claim_of(rule) = calculator_for(rule).claim

  def claim_of_category(category)
    rules_of(category).sum(0.to_d) { |rule| claim_of(rule) }
  end

  def rules_of(category) = rules_by_category.fetch(category.id, [])
  def rules_by_category = @rules_by_category ||= rules.group_by(&:category_id)

  def calculator_for(rule)
    calculators.fetch(rule) { raise UnknownRule, "#{rule.category&.name} is not one of #{user.email}'s rules" }
  end

  def total_claims = @total_claims ||= calculators.values.sum(0.to_d, &:claim)
  delegate :total_money, to: :account_ledger
  delegate :pot, to: :account_ledger
  def free = pot - total_claims
  def account_ledger = @account_ledger ||= AccountLedger.new(user, today: today)

  private

  def calculators
    @calculators ||= rules.index_with do |rule|
      ClaimCalculator.new(rule, today: today, spending: spending_for(rule), adjustments: adjustments_for(rule))
    end
  end

  # The earliest day any rule's walk starts, so one query covers every lane.
  def window_start
    @window_start ||= rules.map { |rule| period_start_of(rule) }.min || current_period.first
  end

  def period_start_of(rule)
    rule.shape == :rate ? current_period.first : user.period_containing(rule.starts_on).first
  end

  def current_period = @current_period ||= user.period_containing(today)

  def spending_for(rule)
    rows = rule.item_id.present? ? item_spending[rule.item_id] : category_spending[rule.category_id]
    Array(rows).map { |_key, day, amount| [day, amount.to_d] }
  end

  def adjustments_for(rule)
    Array(adjustment_rows[rule.id]).map { |_key, day, amount| [day, amount.to_d] }
  end

  def draining
    Entry.expenses.where(categories: { user_id: user.id }).since(window_start)
  end

  def item_spending
    @item_spending ||= begin
      ids = rules.filter_map(&:item_id)
      ids.empty? ? {} : draining.where(item_id: ids).pluck(:item_id, :date, :amount).group_by(&:first)
    end
  end

  def category_spending
    @category_spending ||= begin
      ids = rules.reject { |rule| rule.item_id.present? }.map(&:category_id)
      if ids.empty?
        {}
      else
        draining.on_unruled_items.where(items: { category_id: ids })
          .pluck("items.category_id", :date, :amount).group_by(&:first)
      end
    end
  end

  def adjustment_rows
    @adjustment_rows ||= begin
      ids = rules.map(&:id)
      ids.empty? ? {} : Adjustment.where(rule_id: ids).dated_within(window_start..).pluck(:rule_id, :date, :amount).group_by(&:first)
    end
  end
end
