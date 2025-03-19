class BudgetStatus < ApplicationRecord
  belongs_to :user

  validates :month, presence: true, inclusion: { in: 1..12 }
  validates :year, presence: true
  validates :description, presence: true
  validates :generated_at, presence: true
  validates :month, uniqueness: { scope: [:user_id, :year] }

  before_validation :generate_description, on: :create

  def generate_description
    self.description = BudgetStatusService.call(user, month, year)
    self.generated_at = Date.today
    self
  end
end
