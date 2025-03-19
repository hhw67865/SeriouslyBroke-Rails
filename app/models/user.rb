class User < ApplicationRecord
  include ExpenseCalculable

  has_many :categories, dependent: :destroy
  has_many :expenses, through: :categories
  has_many :income_sources, dependent: :destroy
  has_many :upgrades, through: :income_sources
  has_many :paychecks, through: :income_sources
  has_many :asset_types, dependent: :destroy
  has_many :assets, through: :asset_types
  has_many :asset_transactions, through: :assets
  has_many :budget_statuses, dependent: :destroy

  after_create :create_default_categories
  after_create :create_default_asset_types

  validates :clerk_user_id, presence: true, uniqueness: true

  DEFAULT_CATEGORIES = ["Housing", "Transportation", "Food", "Utilities", "Medical & Healthcare", "Fitness", "Debt Payments", "Personal Care", "Entertainment", "Pets", "Clothes", "Miscellaneous"]
  DEFAULT_ASSET_TYPES = ["Cash", "Checking", "Savings", "Investments", "Real Estate"]

  def create_default_categories
    Category.insert_all(
      DEFAULT_CATEGORIES.map.with_index do |category, index|
        { name: category, user_id: id, order: index + 1 }
      end
    )
  end

  def create_default_asset_types
    AssetType.insert_all(
      DEFAULT_ASSET_TYPES.map do |asset_type|
        { name: asset_type, user_id: id }
      end
    )
  end

  def total_budget(month, year)
    categories.sum(:minimum_amount)
  end

  def total_income(month, year)
    paychecks.where("EXTRACT(MONTH FROM date) = ? AND EXTRACT(YEAR FROM date) = ?", month, year).sum(:amount)
  end

  def exceeding_categories(month, year)
    categories.select do |category|
      category.total_expenses(month, year) > category.minimum_amount && category.minimum_amount > 0
    end
  end

  def all_expenses(month, year)
    start_date = Date.new(year, month, 1).beginning_of_month
    end_date = start_date.end_of_month
    eleven_months_ago = start_date - 11.months

    expenses.where(date: eleven_months_ago..end_date)
            .where("date >= ? OR frequency = ?", start_date, 2)
  end
end
