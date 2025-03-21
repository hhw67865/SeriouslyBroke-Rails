# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable

  has_many :categories, dependent: :destroy
  has_many :savings_pools, dependent: :destroy
  has_many :items, through: :categories
  has_many :entries, through: :items
  has_many :budgets, through: :categories
end
