# frozen_string_literal: true

class SavingsPool < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  has_many :categories, dependent: :nullify
  has_many :items, through: :categories
  has_many :entries, through: :items

  attr_accessor :create_expense_category, :create_savings_category

  validates :name, :target_amount, presence: true
  validates :start_date, presence: true

  after_initialize :set_default_start_date, if: :new_record?
  after_create :create_auto_categories

  # Configure searchable fields
  searchable :name, label: "Name"
  searchable :category, through: :categories, column: :name, label: "Category"

  # Entries scoped to start_date and filtered by category type
  def contribution_entries
    entries.joins(item: :category).where(categories: { category_type: :savings }).where(date: start_date..)
  end

  def withdrawal_entries
    entries.joins(item: :category).where(categories: { category_type: :expense }).where(date: start_date..)
  end

  def timeline_entries
    contribution_entries.or(withdrawal_entries)
  end

  def calculator(as_of: nil)
    SavingsPoolCalculator.new(self, as_of: as_of)
  end

  private

  def set_default_start_date
    self.start_date ||= Date.current
  end

  def create_auto_categories
    create_linked_category(:expense) if boolean_cast(create_expense_category)
    create_linked_category(:savings) if boolean_cast(create_savings_category)
  end

  def create_linked_category(type)
    base_name = "#{name} #{type.to_s.capitalize}"
    categories.create!(
      user: user,
      name: unique_category_name(base_name),
      category_type: type
    )
  end

  def unique_category_name(base_name)
    candidate = base_name
    suffix = 2
    while user.categories.exists?(["LOWER(name) = ?", candidate.downcase])
      candidate = "#{base_name} #{suffix}"
      suffix += 1
    end
    candidate
  end

  def boolean_cast(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
