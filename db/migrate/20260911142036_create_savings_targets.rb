# frozen_string_literal: true

class CreateSavingsTargets < ActiveRecord::Migration[8.1]
  def change
    create_table :savings_targets, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :item, type: :uuid, foreign_key: true, index: false
      t.money :amount, scale: 2
      t.decimal :percent, precision: 5, scale: 2
      t.date :starts_on, null: false
      t.timestamps
    end
    add_index :savings_targets, :account_id, unique: true, where: "item_id IS NULL", name: "index_savings_targets_one_fixed_per_account"
    add_index :savings_targets, [:account_id, :item_id], unique: true, where: "item_id IS NOT NULL", name: "index_savings_targets_one_share_per_item"
    add_check_constraint :savings_targets,
                         "(item_id IS NULL AND amount IS NOT NULL AND percent IS NULL) OR (item_id IS NOT NULL AND percent IS NOT NULL AND amount IS NULL)",
                         name: "savings_targets_one_figure"
    add_check_constraint :savings_targets, "amount IS NULL OR amount > 0::money", name: "savings_targets_positive_amount"
    add_check_constraint :savings_targets, "percent IS NULL OR (percent > 0 AND percent <= 100)", name: "savings_targets_percent_range"
  end
end
