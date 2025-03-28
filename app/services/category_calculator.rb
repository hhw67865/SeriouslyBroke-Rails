class CategoryCalculator
  attr_reader :category, :date_range

  def initialize(category, date = Date.current)
    @category = category
    @date_range = date.beginning_of_month..date.end_of_month
  end

  # Shared methods
  def total_amount
    category.entries.where(date: date_range).sum(:amount)
  end

  # Expense methods
  def budget_percentage
    return 0 unless category.expense? && category.budget&.amount.to_f > 0
    (total_amount / category.budget.amount * 100).round
  end

  # Income methods
  def previous_month_change_percentage
    return 0 unless category.income?
    
    prev_month = 1.month.ago
    prev_range = prev_month.beginning_of_month..prev_month.end_of_month
    prev_amount = category.entries.where(date: prev_range).sum(:amount)
    
    return 0 if prev_amount == 0
    ((total_amount - prev_amount) / prev_amount.to_f * 100).round
  end

  def previous_month_trend
    percentage = previous_month_change_percentage
    percentage >= 0 ? :up : :down
  end

  # Savings methods
  def monthly_contribution
    return 0 unless category.savings?
    total_amount
  end

  # For all categories
  def top_items(limit = 3)
    items_with_amounts = {}
    
    category.items.each do |item|
      amount = item.entries.where(date: date_range).sum(:amount)
      items_with_amounts[item] = amount if amount > 0
    end
    
    items_with_amounts.sort_by { |_, amount| -amount }.first(limit).to_h
  end
end 