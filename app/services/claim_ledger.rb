# frozen_string_literal: true

# Every claim on checking for one user, fed in a fixed number of queries: each rule's lane spending
# and adjustments, and each savings account's targets, transfers in, share income and adjustments —
# plus one per distinct share item for typical income.
class ClaimLedger
  class UnknownSource < StandardError; end

  KIND_RANK = { choice: 0, usage: 1, savings: 2, bill: 3 }.freeze

  # One claim as every screen reads it. `source` is a Rule or an Account.
  Claim = Data.define(:source, :name, :kind, :claim, :ask, :cuttable) do
    def rank = KIND_RANK.fetch(kind)
    def rule? = source.is_a?(Rule)
    def account? = source.is_a?(Account)
    def cuttable? = cuttable
  end

  attr_reader :user, :today

  def initialize(user, today: user.today)
    @user = user
    @today = today
  end

  def rules = @rules ||= user.rules.includes(:item, category: :user).to_a

  # Every non-main account carrying a target, with its targets loaded.
  def savings_accounts
    @savings_accounts ||= user.accounts.where(id: SavingsTarget.select(:account_id))
      .where.not(id: user.main_account_id).includes(savings_targets: :item).order(:name).to_a
  end

  def claim_of(rule) = calculator_for(rule).claim
  def claim_of_category(category) = rules_of(category).sum(0.to_d) { |rule| claim_of(rule) }
  def rules_of(category) = rules_by_category.fetch(category.id, [])
  def rules_by_category = @rules_by_category ||= rules.group_by(&:category_id)

  def calculator_for(source)
    calculators.fetch(source) { raise UnknownSource, "#{source.class} #{source.id} is not one of #{user.email}'s claim sources" }
  end

  def claims = @claims ||= (rule_claims + account_claims).sort_by { |claim| give_way_key(claim) }
  def rule_claims = @rule_claims ||= rules.map { |rule| rule_claim(rule) }
  def account_claims = @account_claims ||= savings_accounts.map { |account| account_claim(account) }

  def budget = @budget ||= rule_claims.sum(0.to_d, &:ask)
  def savings = @savings ||= account_claims.sum(0.to_d, &:ask)
  def budget_claim = @budget_claim ||= rule_claims.sum(0.to_d, &:claim)
  def savings_claim = @savings_claim ||= account_claims.sum(0.to_d, &:claim)
  def claimed = budget_claim + savings_claim
  def free = pot - claimed

  delegate :total_money, :pot, to: :account_ledger
  def account_ledger = @account_ledger ||= AccountLedger.new(user, today: today)

  private

  def rule_claim(rule)
    calculator = calculator_for(rule)
    Claim.new(
      source: rule,
      name: rule.item&.name || rule.category.name,
      kind: rule.rule_type.to_sym,
      claim: calculator.claim,
      ask: calculator.ask,
      cuttable: rule.cadence != :every_n
    )
  end

  def account_claim(account)
    calculator = calculator_for(account)
    Claim.new(source: account, name: account.name, kind: :savings, claim: calculator.claim, ask: calculator.ask, cuttable: true)
  end

  # Kind first; then, among rules, the category lowest in the fill order gives way first.
  def give_way_key(claim)
    [claim.rank, claim.rule? ? -claim.source.category.priority : 0, -claim.claim, claim.name]
  end

  def calculators = @calculators ||= rule_calculators.merge(account_calculators)

  def rule_calculators
    rules.index_with do |rule|
      ClaimCalculator.new(rule, today: today, spending: spending_for(rule), adjustments: rule_adjustments_for(rule))
    end
  end

  def account_calculators
    savings_accounts.index_with do |account|
      SavingsCalculator.new(
        account,
        today: today,
        targets: account.savings_targets.to_a,
        transfers: rows_of(transfer_rows, account.id),
        income: share_income_rows,
        adjustments: rows_of(account_adjustment_rows, account.id),
        typical_income_by_item: typical_income_by_item
      )
    end
  end

  def rows_of(grouped, key) = Array(grouped[key]).map { |_key, day, amount| [day, amount.to_d] }

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

  def rule_adjustments_for(rule) = rows_of(rule_adjustment_rows, rule.id)

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

  def rule_adjustment_rows
    @rule_adjustment_rows ||= begin
      ids = rules.map(&:id)
      ids.empty? ? {} : Adjustment.on_rules(ids).dated_within(window_start..).pluck(:source_id, :date, :amount).group_by(&:first)
    end
  end

  # Savings rows. Every account's walk starts at its own earliest target; one query from the
  # earliest of those covers them all, and each calculator ignores what precedes its own start.
  def savings_start = @savings_start ||= savings_accounts.flat_map(&:savings_targets).map(&:starts_on).min

  def transfer_rows
    @transfer_rows ||= begin
      ids = savings_accounts.map(&:id)
      ids.empty? ? {} : Transfer.where(to_account_id: ids, date: savings_start..).pluck(:to_account_id, :date, :amount).group_by(&:first)
    end
  end

  def share_item_ids = @share_item_ids ||= savings_accounts.flat_map(&:savings_targets).filter_map(&:item_id).uniq

  def share_income_rows
    @share_income_rows ||= if share_item_ids.empty?
                             {}
                           else
                             Entry.where(item_id: share_item_ids, date: savings_start..).pluck(:item_id, :date, :amount)
                               .group_by(&:first).transform_values { |rows| rows.map { |_id, day, amount| [day, amount.to_d] } }
                           end
  end

  def account_adjustment_rows
    @account_adjustment_rows ||= begin
      ids = savings_accounts.map(&:id)
      ids.empty? ? {} : Adjustment.on_accounts(ids).pluck(:source_id, :date, :amount).group_by(&:first)
    end
  end

  def typical_income_by_item = @typical_income_by_item ||= account_ledger.typical_income_of_items(share_item_ids)
end
