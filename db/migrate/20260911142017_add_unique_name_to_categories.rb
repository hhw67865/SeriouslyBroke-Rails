# frozen_string_literal: true

class AddUniqueNameToCategories < ActiveRecord::Migration[8.1]
  def change
    add_index :categories, "user_id, lower(name)", unique: true, name: "index_categories_on_user_id_and_lower_name"
  end
end
