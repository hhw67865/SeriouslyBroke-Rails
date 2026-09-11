# frozen_string_literal: true

class AddPriorityToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :priority, :integer, null: false, default: 0
    add_check_constraint :categories, "priority >= 0", name: "categories_priority_non_negative"
  end
end
