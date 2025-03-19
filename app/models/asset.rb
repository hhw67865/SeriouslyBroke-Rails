class Asset < ApplicationRecord
  belongs_to :asset_type
  has_many :asset_transactions, dependent: :destroy

  validates :name, uniqueness: { scope: :asset_type_id }

  def value
    asset_transactions.sum(:amount)
  end
end
