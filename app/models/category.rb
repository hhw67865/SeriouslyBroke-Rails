class Category < ApplicationRecord
  include ExpenseCalculable

  belongs_to :user
  has_many :expenses, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :order, uniqueness: { scope: :user_id }

  before_validation :ensure_order, on: :create

  def minimum_amount
    super || 0
  end

  private

  def ensure_order
    self.order ||= (user.categories.maximum(:order) || 0) + 1
  end
end
