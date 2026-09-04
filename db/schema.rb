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

ActiveRecord::Schema[8.1].define(version: 2026_09_05_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "account_movements", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.money "amount", scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "date", null: false
    t.uuid "from_pool_id", null: false
    t.integer "kind", default: 0, null: false
    t.uuid "source_entry_id"
    t.uuid "to_pool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_account_movements_on_date"
    t.index ["from_pool_id"], name: "index_account_movements_on_from_pool_id"
    t.index ["source_entry_id"], name: "index_account_movements_on_source_entry_id"
    t.index ["to_pool_id"], name: "index_account_movements_on_to_pool_id"
    t.check_constraint "amount > 0::money", name: "account_movements_positive_amount"
    t.check_constraint "from_pool_id <> to_pool_id", name: "account_movements_distinct_accounts"
    t.check_constraint "kind = 0", name: "account_movements_are_transfers"
  end

  create_table "adjustments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.money "amount", scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "date", null: false
    t.uuid "rule_id", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_adjustments_on_date"
    t.index ["rule_id"], name: "index_adjustments_on_rule_id"
    t.check_constraint "amount <> 0::money", name: "adjustments_non_zero_amount"
  end

  create_table "budgets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.money "amount", scale: 2, null: false
    t.date "anchor_date"
    t.integer "basis", default: 0, null: false
    t.boolean "carries_over", default: false, null: false
    t.uuid "category_id", null: false
    t.datetime "created_at", null: false
    t.integer "interval_months"
    t.uuid "item_id"
    t.integer "rule_type", default: 1, null: false
    t.money "target_amount", scale: 2
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_budgets_on_category_id"
    t.index ["item_id"], name: "index_budgets_on_item_id"
    t.index ["item_id"], name: "index_budgets_on_item_id_unique", unique: true, where: "(item_id IS NOT NULL)"
    t.check_constraint "target_amount > 0::money", name: "budgets_positive_target_amount"
  end

  create_table "categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "category_type", null: false
    t.string "color"
    t.datetime "created_at", null: false
    t.date "funded_since"
    t.string "name", null: false
    t.integer "priority", default: 0, null: false
    t.money "target_amount", scale: 2
    t.boolean "tracked", default: true, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_categories_on_user_id"
  end

  create_table "entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.money "amount", scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "date", null: false
    t.text "description"
    t.uuid "item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_entries_on_item_id"
  end

  create_table "items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "category_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_items_on_category_id"
  end

  create_table "pools", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "pool_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index "user_id, lower((name)::text)", name: "index_pools_on_user_id_and_lower_name", unique: true
    t.index ["user_id"], name: "index_pools_on_user_id"
    t.check_constraint "pool_type = 0", name: "pools_are_accounts"
  end

  create_table "suggestion_dismissals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.uuid "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["subject_type", "subject_id"], name: "index_suggestion_dismissals_on_subject"
    t.index ["user_id", "kind", "subject_type", "subject_id"], name: "index_suggestion_dismissals_on_user_and_subject", unique: true
    t.index ["user_id"], name: "index_suggestion_dismissals_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.uuid "default_account_id"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
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
    t.money "typical_income", scale: 2
    t.datetime "updated_at", null: false
    t.index ["default_account_id"], name: "index_users_on_default_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "account_movements", "entries", column: "source_entry_id"
  add_foreign_key "account_movements", "pools", column: "from_pool_id"
  add_foreign_key "account_movements", "pools", column: "to_pool_id"
  add_foreign_key "adjustments", "budgets", column: "rule_id"
  add_foreign_key "budgets", "categories"
  add_foreign_key "budgets", "items"
  add_foreign_key "categories", "users"
  add_foreign_key "entries", "items"
  add_foreign_key "items", "categories"
  add_foreign_key "pools", "users"
  add_foreign_key "suggestion_dismissals", "users"
  add_foreign_key "users", "pools", column: "default_account_id", on_delete: :nullify
end
