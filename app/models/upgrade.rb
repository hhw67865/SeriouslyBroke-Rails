class Upgrade < ApplicationRecord
  belongs_to :income_source
  has_many :tasks, dependent: :destroy
  belongs_to :user
end
