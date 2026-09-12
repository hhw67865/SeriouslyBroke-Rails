# frozen_string_literal: true

class AddShapeToRules < ActiveRecord::Migration[8.1]
  def change
    change_table :rules, bulk: true do |t|
      t.integer :rule_type, null: false, default: 1
      t.date :starts_on
      t.date :anchor_date
      t.integer :interval_months
      t.boolean :keeps_unspent, null: false, default: false
    end
    add_check_constraint :rules, "amount > 0::money", name: "rules_positive_amount"
    add_check_constraint :rules, "interval_months IS NULL OR interval_months > 0", name: "rules_positive_interval"
    add_check_constraint :rules, "NOT (keeps_unspent AND anchor_date IS NOT NULL)", name: "rules_keeping_never_dates"
    add_check_constraint :rules, "interval_months IS NULL OR anchor_date IS NOT NULL", name: "rules_interval_needs_a_date"
  end
end
