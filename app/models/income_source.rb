class IncomeSource < ApplicationRecord
  belongs_to :user
  has_many :paychecks, dependent: :destroy
  has_one :upgrade, dependent: :destroy
  has_one :assets

  validates :name, presence: true

  def total_income(month, year)
    paychecks.where("EXTRACT(MONTH FROM date) = ? AND EXTRACT(YEAR FROM date) = ?", month, year).sum(:amount)
  end
end
