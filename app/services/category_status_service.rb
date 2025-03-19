class CategoryStatusService

  def initialize(user, month, year)
    @user = user
    @month = month
    @year = year
  end

  def self.call(user, month, year)
    new(user, month, year).call
  end

  def call
    current_date = Date.new(year, month, 1)
    previous_date = current_date.prev_month

    {
      month:,
      year:,
      current_month: current_date.strftime("%B %Y"),
      previous_month: previous_date.strftime("%B %Y"),
      categories: user.categories.order(:order).map do |category|
        {
          name: category.name,
          total_expenses: category.total_expenses(month, year),
          prev_total_expenses: category.total_expenses(previous_date.month, previous_date.year),
          budget: category.minimum_amount,
        }
      end
    }
  end

  private

  attr_reader :user, :month, :year
end
