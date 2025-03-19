class AssetType < ApplicationRecord
  belongs_to :user
  has_many :assets, dependent: :destroy

  validates :name, uniqueness: { scope: :user_id }

  def total_value
    assets.sum(&:value)
  end
end
