# frozen_string_literal: true

class Entry < ApplicationRecord
  include ModelSearchable
  
  belongs_to :item
  accepts_nested_attributes_for :item

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true

  delegate :user, to: :item
  delegate :category, to: :item

  scope :expenses, -> { joins(item: :category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(item: :category).where(categories: { category_type: :income }) }
  scope :savings, -> { joins(item: :category).where(categories: { category_type: :savings }) }

  # Define searchable fields using the DSL
  searchable :description, label: "Description"
  searchable :date, type: :date, label: "Date"
  searchable :item, through: :item, column: :name, label: "Item"
  searchable :category, through: [:item, :category], column: :name, label: "Category"
end
