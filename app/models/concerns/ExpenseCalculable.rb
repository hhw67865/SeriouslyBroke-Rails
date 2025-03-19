module ExpenseCalculable
  extend ActiveSupport::Concern

  def total_expenses(month, year)
    start_date = Date.new(year, month, 1)
    end_date = start_date.end_of_month

    # Daily and monthly expenses
    regular_expenses = expenses.where(frequency: [0, 1])
                               .where(date: start_date..end_date)
                               .sum(:amount)

    # Annual expenses
    annual_expenses = expenses.where(frequency: 2)
                              .where("date > ? AND date <= ?", end_date - 1.year, end_date)
                              .sum("amount / 12.0")

    regular_expenses + annual_expenses
  end

  def last_month_total
    last_month = Date.today.last_month
    total_expenses(last_month.month, last_month.year)
  end

  def last_three_month_average
    (2.downto(0).sum do |months_ago|
      date = Date.today.months_ago(months_ago)
      total_expenses(date.month, date.year)
    end) / 3
  end

  def current_month_total
    today = Date.today
    total_expenses(today.month, today.year)
  end
end