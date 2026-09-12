# frozen_string_literal: true

class AddItemToRules < ActiveRecord::Migration[8.1]
  def change
    add_reference :rules, :item, type: :uuid, foreign_key: true, index: false
    add_index :rules, :item_id, unique: true, where: "item_id IS NOT NULL", name: "index_rules_on_item_id_unique"
    add_index :rules, :category_id, unique: true, where: "item_id IS NULL", name: "index_rules_one_item_less_per_category"
  end
end
