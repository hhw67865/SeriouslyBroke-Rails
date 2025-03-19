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

ActiveRecord::Schema[7.1].define(version: 2024_12_07_202416) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "bloom"
  enable_extension "btree_gin"
  enable_extension "btree_gist"
  enable_extension "citext"
  enable_extension "cube"
  enable_extension "dblink"
  enable_extension "dict_int"
  enable_extension "dict_xsyn"
  enable_extension "earthdistance"
  enable_extension "fuzzystrmatch"
  enable_extension "hstore"
  enable_extension "intagg"
  enable_extension "intarray"
  enable_extension "isn"
  enable_extension "lo"
  enable_extension "ltree"
  enable_extension "pg_buffercache"
  enable_extension "pg_prewarm"
  enable_extension "pg_stat_statements"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "pgrowlocks"
  enable_extension "pgstattuple"
  enable_extension "plpgsql"
  enable_extension "tablefunc"
  enable_extension "unaccent"
  enable_extension "uuid-ossp"

  create_table "asset_transactions", force: :cascade do |t|
    t.date "date"
    t.money "amount", scale: 2
    t.text "description"
    t.bigint "asset_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id", "date"], name: "index_asset_transactions_on_asset_id_and_date"
    t.index ["asset_id"], name: "index_asset_transactions_on_asset_id"
    t.index ["date"], name: "index_asset_transactions_on_date"
  end

  create_table "asset_types", force: :cascade do |t|
    t.string "name"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_asset_types_on_user_id"
  end

  create_table "assets", force: :cascade do |t|
    t.string "name"
    t.bigint "asset_type_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_type_id"], name: "index_assets_on_asset_type_id"
  end

  create_table "budget_statuses", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "month"
    t.integer "year"
    t.text "description"
    t.datetime "generated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["generated_at"], name: "index_budget_statuses_on_generated_at"
    t.index ["user_id", "month", "year"], name: "index_budget_statuses_on_user_id_and_month_and_year", unique: true
    t.index ["user_id"], name: "index_budget_statuses_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name"
    t.money "minimum_amount", scale: 2
    t.string "color"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "order"
    t.index ["user_id", "order"], name: "index_categories_on_user_id_and_order", unique: true
    t.index ["user_id"], name: "index_categories_on_user_id"
  end

  create_table "expenses", force: :cascade do |t|
    t.string "name"
    t.money "amount", scale: 2
    t.date "date"
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "frequency"
    t.index ["category_id", "date"], name: "index_expenses_on_category_id_and_date"
    t.index ["category_id"], name: "index_expenses_on_category_id"
    t.index ["date"], name: "index_expenses_on_date"
    t.index ["frequency"], name: "index_expenses_on_frequency"
  end

  create_table "income_sources", force: :cascade do |t|
    t.string "name"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_income_sources_on_user_id"
  end

  create_table "paychecks", force: :cascade do |t|
    t.date "date"
    t.money "amount", scale: 2
    t.bigint "income_source_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.index ["date"], name: "index_paychecks_on_date"
    t.index ["income_source_id", "date"], name: "index_paychecks_on_income_source_id_and_date"
    t.index ["income_source_id"], name: "index_paychecks_on_income_source_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.text "description"
    t.boolean "completed"
    t.bigint "upgrade_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["upgrade_id"], name: "index_tasks_on_upgrade_id"
  end

  create_table "upgrades", force: :cascade do |t|
    t.money "potential_income", scale: 2
    t.money "minimum_downpayment", scale: 2
    t.bigint "income_source_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["income_source_id"], name: "index_upgrades_on_income_source_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "clerk_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "asset_transactions", "assets"
  add_foreign_key "asset_types", "users"
  add_foreign_key "assets", "asset_types"
  add_foreign_key "budget_statuses", "users"
  add_foreign_key "categories", "users"
  add_foreign_key "expenses", "categories"
  add_foreign_key "income_sources", "users"
  add_foreign_key "paychecks", "income_sources"
  add_foreign_key "tasks", "upgrades"
  add_foreign_key "upgrades", "income_sources"
end
