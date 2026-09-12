# frozen_string_literal: true

class AddRegularToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :regular, :boolean, null: false, default: true
  end
end
