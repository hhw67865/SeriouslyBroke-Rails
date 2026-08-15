# frozen_string_literal: true

class AddPoolModeToBudgets < ActiveRecord::Migration[8.1]
  def change
    change_column_null :budgets, :category_id, true

    add_reference :budgets, :pool, type: :uuid, foreign_key: true, null: true
    add_reference :budgets, :item, type: :uuid, foreign_key: true, null: true

    add_column :budgets, :interval_months, :integer
    add_column :budgets, :anchor_date, :date
    add_column :budgets, :basis, :integer, null: false, default: 0

    add_index :budgets, :item_id, unique: true, where: "item_id IS NOT NULL",
                        name: "index_budgets_on_item_id_unique"
  end
end
