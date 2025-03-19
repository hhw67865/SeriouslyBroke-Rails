class GraphService
  def initialize(user, month, year)
    @user = user
    @month = month
    @year = year
  end

  def self.call(user, month, year)
    new(user, month, year).call
  end

  def call
    {
      month:,
      year:,
      expenses_graph_data:,
      total_budget:,
      total_expenses:,
      prev_total_expenses:,
      total_income:
    }
  end

  private

  attr_reader :user, :month, :year

  def expenses_graph_data
    current_expenses = fetch_expenses_by_day(month, year)
    prev_month = month == 1 ? 12 : month - 1
    prev_year = month == 1 ? year - 1 : year
    prev_expenses = fetch_expenses_by_day(prev_month, prev_year)

    running_total = 0.0
    prev_running_total = 0.0

    days_in_month.map do |day|
      expense = current_expenses[day] || 0
      prev_expense = prev_expenses[day.prev_month] || 0
      running_total += expense
      prev_running_total += prev_expense

      {
        date: I18n.l(day, format: '%-m/%-d'),
        total: (day > Time.zone.today ? nil : running_total.round(2)),
        prev_total: prev_running_total.round(2),
        budget: total_budget.round(2)
      }
    end
  end

  def fetch_expenses_by_day(month, year)
    start_date = Date.new(year, month, 1)
    end_date = start_date.end_of_month

    # Fetch daily and monthly expenses
    regular_expenses = user.expenses
                           .where(frequency: [0, 1])
                           .where(date: start_date..end_date)
                           .group(:date)
                           .sum(:amount)

    # Fetch annual expenses
    annual_expenses = user.expenses
                          .where(frequency: 2)
                          .where("date > ? AND date <= ?", end_date - 1.year, end_date)
                          .select('date, amount')

    # Combine regular and prorated annual expenses
    combined_expenses = regular_expenses.to_h

    annual_expenses.each do |expense|
      prorate_annual_expense(expense, start_date, end_date, combined_expenses)
    end

    combined_expenses.transform_keys(&:to_date)
  end

  def prorate_annual_expense(expense, start_date, end_date, combined_expenses)
    prorated_amount = expense.amount / 12.0
    expense_day = expense.date.day

    target_day = if [28, 29, 30, 31].include?(expense_day)
                   end_date.day
                 else
                   expense_day
                 end

    target_date = Date.new(end_date.year, end_date.month, target_day)
    combined_expenses[target_date] ||= 0
    combined_expenses[target_date] += prorated_amount
  end

  def days_in_month
    (Date.new(year, month, 1)..Date.new(year, month, -1))
  end

  def total_budget
    @total_budget ||= user.total_budget(month, year)
  end

  def total_expenses
    @total_expenses ||= user.total_expenses(month, year)
  end

  def prev_total_expenses
    month == 1 ? user.total_expenses(12, year - 1) : user.total_expenses(month - 1, year)
  end

  def total_income
    @total_income ||= user.total_income(month, year)
  end


  # PIE CHART DATA TODO

  def expense_per_category
    user.categories.map do |category|
      total_expense = category.total_expenses(month, year)
      next if total_expense.zero?
  
      {
        name: category.name,
        total_expense:
      }
    end.compact
  end

  def income_per_source
    user.income_sources.map do |source|
      total_income = source.total_income(month, year)
      next if total_income.zero?

      {
        name: source.name,
        total_income:
      }
    end.compact
  end
end
