# frozen_string_literal: true

# Everything the accounts-and-rules schema adds. Nothing here reads data, so it is reversible as
# written; the data migration that follows fills the nullable columns and removes main's shape.
class AccountsAndRulesSchema < ActiveRecord::Migration[8.1]
  def change
    create_accounts
    create_transfers
    extend_users
    extend_categories
    extend_entries
    reshape_rules
    create_adjustments
  end

  private

  def create_accounts
    create_table :accounts, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.money :opening_balance, scale: 2, null: false, default: 0
      t.date :opened_on
      t.timestamps
    end
    add_index :accounts, "user_id, lower(name)", unique: true, name: "index_accounts_on_user_id_and_lower_name"
  end

  def create_transfers
    create_table :transfers, id: :uuid do |t|
      t.references :from_account, type: :uuid, null: false, foreign_key: { to_table: :accounts }
      t.references :to_account, type: :uuid, null: false, foreign_key: { to_table: :accounts }
      t.money :amount, scale: 2, null: false
      t.date :date, null: false
      t.timestamps
    end
    add_index :transfers, :date
    add_check_constraint :transfers, "amount > 0::money", name: "transfers_positive_amount"
    add_check_constraint :transfers, "from_account_id <> to_account_id", name: "transfers_distinct_accounts"
  end

  def extend_users
    add_reference :users, :main_account, type: :uuid, foreign_key: { to_table: :accounts, on_delete: :nullify }
    add_column :users, :period_cadence, :integer
    add_column :users, :period_anchor_date, :date
  end

  def extend_categories
    add_column :categories, :priority, :integer, null: false, default: 0
    add_column :categories, :regular, :boolean, null: false, default: true
    add_check_constraint :categories, "priority >= 0", name: "categories_priority_non_negative"
    add_index :categories, "user_id, lower(name)", unique: true, name: "index_categories_on_user_id_and_lower_name"
  end

  def extend_entries
    add_column :entries, :day, :date
    add_reference :entries, :account, type: :uuid, foreign_key: true
    add_check_constraint :entries, "amount > 0::money", name: "entries_positive_amount"
  end

  def reshape_rules
    rename_table :budgets, :rules
    add_reference :rules, :item, type: :uuid, foreign_key: true, index: false
    add_column :rules, :rule_type, :integer, null: false, default: 1
    add_column :rules, :starts_on, :date
    add_column :rules, :anchor_date, :date
    add_column :rules, :interval_months, :integer
    add_column :rules, :keeps_unspent, :boolean, null: false, default: false
    add_check_constraint :rules, "amount > 0::money", name: "rules_positive_amount"
    add_check_constraint :rules, "interval_months IS NULL OR interval_months > 0", name: "rules_positive_interval"
    add_check_constraint :rules, "NOT (keeps_unspent AND anchor_date IS NOT NULL)", name: "rules_keeping_never_dates"
    add_check_constraint :rules, "interval_months IS NULL OR anchor_date IS NOT NULL", name: "rules_interval_needs_a_date"
    add_index :rules, :item_id, unique: true, where: "item_id IS NOT NULL", name: "index_rules_on_item_id_unique"
    add_index :rules, :category_id, unique: true, where: "item_id IS NULL", name: "index_rules_one_item_less_per_category"
  end

  def create_adjustments
    create_table :adjustments, id: :uuid do |t|
      t.references :rule, type: :uuid, null: false, foreign_key: true
      t.money :amount, scale: 2, null: false
      t.date :date, null: false
      t.timestamps
    end
    add_index :adjustments, :date
    add_check_constraint :adjustments, "amount <> 0::money", name: "adjustments_non_zero_amount"
  end
end
