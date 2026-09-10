# frozen_string_literal: true

class Category < ApplicationRecord
  include ModelSearchable

  DEFAULT_COLOR = "#C9C78B"
  RULES_KEEP_IT_AN_EXPENSE = "can't become income while it has rules — delete them first"

  belongs_to :user, touch: true
  has_many :items, dependent: :destroy
  has_many :entries, through: :items
  has_many :rules, dependent: :destroy

  normalizes :name, with: ->(name) { name.squish }

  enum :category_type, { expense: 0, income: 1 }

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :category_type, presence: true
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :rules_keep_it_an_expense

  after_update :entries_return_to_main_when_no_longer_income

  scope :expenses, -> { where(category_type: :expense) }
  scope :incomes, -> { where(category_type: :income) }
  scope :tracked, -> { where(tracked: true) }
  scope :untracked, -> { where(tracked: false) }
  scope :regular, -> { where(regular: true) }
  scope :with_a_rule, -> { where(id: Rule.select(:category_id)) }
  # The give-way order on the home page: lower priority gives way first.
  scope :in_fill_order, -> { expenses.with_a_rule.order(:priority, :name) }
  scope :with_type, ->(type) { (type.to_s == "income" ? incomes : expenses).includes(:items) }

  searchable :name, label: "Name"

  # Rewrites priorities to match the submitted order. The list must be exactly the user's ruled
  # expense categories, once each; anything else is refused with nothing written.
  def self.apply_fill_order(user:, category_ids:)
    ids = Array(category_ids).map(&:to_s)
    return false if ids.empty? || ids.uniq.size != ids.size

    transaction do
      user.lock!
      ordered = user.categories.in_fill_order.to_a
      matches = ordered.map { |category| category.id.to_s }.sort == ids.sort
      write_fill_order(ordered, ids) if matches
      matches
    end
  end

  def self.write_fill_order(ordered, ids)
    by_id = ordered.index_by { |category| category.id.to_s }
    ids.each_with_index { |id, index| by_id.fetch(id).update!(priority: index) }
  end
  private_class_method :write_fill_order

  # Sets which of the user's income categories feed typical income. Unknown ids are dropped by
  # the scope itself; expense categories are never in it.
  def self.choose_regular_income(user:, category_ids:)
    chosen = Array(category_ids).to_set(&:to_s)

    transaction do
      incomes = user.categories.incomes.to_a
      incomes.each { |category| category.update!(regular: chosen.include?(category.id.to_s)) }
      incomes.count(&:regular?)
    end
  end

  def display_color = color.presence || DEFAULT_COLOR

  def ruled? = rules.load.any?

  def stats(date = user.today, period: :monthly)
    CategoryStats.new(self, date, period: period)
  end

  private

  def rules_keep_it_an_expense
    return unless category_type_change == ["expense", "income"] && rules.exists?

    errors.add(:category_type, RULES_KEEP_IT_AN_EXPENSE)
  end

  def entries_return_to_main_when_no_longer_income
    return unless saved_change_to_category_type == ["income", "expense"]

    entries.update_all(account_id: nil) # rubocop:disable Rails/SkipsModelValidations
  end
end
