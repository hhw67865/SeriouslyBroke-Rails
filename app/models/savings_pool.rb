# frozen_string_literal: true

class SavingsPool < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  has_many :categories, dependent: :nullify
  has_many :items, through: :categories
  has_many :entries, through: :items

  validates :name, :target_amount, presence: true
  validates :start_date, presence: true

  after_initialize :set_default_start_date, if: :new_record?

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

  def calculator(as_of: nil)
    SavingsPoolCalculator.new(self, as_of: as_of)
  end

  private

  def set_default_start_date
    self.start_date ||= Date.current
  end
end
