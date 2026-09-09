# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_10_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.date "opened_on"
    t.money "opening_balance", scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index "user_id, lower((name)::text)", name: "index_accounts_on_user_id_and_lower_name", unique: true
    t.index ["user_id"], name: "index_accounts_on_user_id"
  end

  create_table "adjustments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.money "amount", scale: 2, null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.uuid "rule_id", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_adjustments_on_date"
    t.index ["rule_id"], name: "index_adjustments_on_rule_id"
    t.check_constraint "amount <> 0::money", name: "adjustments_non_zero_amount"
  end

  create_table "categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "category_type", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "priority", default: 0, null: false
    t.boolean "regular", default: true, null: false
    t.uuid "savings_pool_id"
    t.boolean "tracked", default: true, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index "user_id, lower((name)::text)", name: "index_categories_on_user_id_and_lower_name", unique: true
    t.index ["savings_pool_id"], name: "index_categories_on_savings_pool_id"
    t.index ["user_id"], name: "index_categories_on_user_id"
    t.check_constraint "priority >= 0", name: "categories_priority_non_negative"
  end

  create_table "entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.money "amount", scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "date", null: false
    t.date "day"
    t.text "description"
    t.uuid "item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_entries_on_account_id"
    t.index ["item_id"], name: "index_entries_on_item_id"
    t.check_constraint "amount > 0::money", name: "entries_positive_amount"
  end

  create_table "items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "category_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_items_on_category_id"
  end

  create_table "rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.money "amount", scale: 2, null: false
    t.date "anchor_date"
    t.uuid "category_id", null: false
    t.datetime "created_at", null: false
    t.integer "interval_months"
    t.uuid "item_id"
    t.boolean "keeps_unspent", default: false, null: false
    t.boolean "prorated", default: false, null: false
    t.integer "rule_type", default: 1, null: false
    t.date "starts_on"
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_rules_on_category_id"
    t.index ["category_id"], name: "index_rules_one_item_less_per_category", unique: true, where: "(item_id IS NULL)"
    t.index ["item_id"], name: "index_rules_on_item_id_unique", unique: true, where: "(item_id IS NOT NULL)"
    t.check_constraint "NOT (keeps_unspent AND anchor_date IS NOT NULL)", name: "rules_keeping_never_dates"
    t.check_constraint "amount > 0::money", name: "rules_positive_amount"
    t.check_constraint "interval_months IS NULL OR anchor_date IS NOT NULL", name: "rules_interval_needs_a_date"
    t.check_constraint "interval_months IS NULL OR interval_months > 0", name: "rules_positive_interval"
  end

  create_table "savings_pools", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.date "start_date"
    t.money "target_amount", scale: 2
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_savings_pools_on_user_id"
  end

  create_table "transfers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.money "amount", scale: 2, null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.uuid "from_account_id", null: false
    t.uuid "to_account_id", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_transfers_on_date"
    t.index ["from_account_id"], name: "index_transfers_on_from_account_id"
    t.index ["to_account_id"], name: "index_transfers_on_to_account_id"
    t.check_constraint "amount > 0::money", name: "transfers_positive_amount"
    t.check_constraint "from_account_id <> to_account_id", name: "transfers_distinct_accounts"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.uuid "main_account_id"
    t.boolean "ming_mode", default: false, null: false
    t.string "name"
    t.date "period_anchor_date"
    t.integer "period_cadence"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.integer "theme", default: 0, null: false
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["main_account_id"], name: "index_users_on_main_account_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "accounts", "users"
  add_foreign_key "adjustments", "rules"
  add_foreign_key "categories", "savings_pools"
  add_foreign_key "categories", "users"
  add_foreign_key "entries", "accounts"
  add_foreign_key "entries", "items"
  add_foreign_key "items", "categories"
  add_foreign_key "rules", "categories"
  add_foreign_key "rules", "items"
  add_foreign_key "savings_pools", "users"
  add_foreign_key "transfers", "accounts", column: "from_account_id"
  add_foreign_key "transfers", "accounts", column: "to_account_id"
  add_foreign_key "users", "accounts", column: "main_account_id", on_delete: :nullify
end
