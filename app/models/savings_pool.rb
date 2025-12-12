# frozen_string_literal: true

class SavingsPool < ApplicationRecord
  include ModelSearchable

  belongs_to :user
  has_many :categories, dependent: :nullify
  has_many :items, through: :categories
  has_many :entries, through: :items

  validates :name, :target_amount, presence: true
  validates :start_date, presence: true

  after_initialize :set_default_start_date, if: :new_record?

  # Configure searchable fields
  searchable :name, label: "Name"
  searchable :category, through: :categories, column: :name, label: "Category"

  # Calculator for savings pool metrics
  def calculator
    @calculator ||= SavingsPoolCalculator.new(self)
  end

  private

  def set_default_start_date
    self.start_date ||= Date.current
  end
end
