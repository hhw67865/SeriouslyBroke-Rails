class SavingsPool < ApplicationRecord
  belongs_to :user
  has_many :categories, dependent: :nullify
  has_many :items, through: :categories
  has_many :entries, through: :items

  validates :name, :target_amount, presence: true
end
