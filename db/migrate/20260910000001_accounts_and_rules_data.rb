# frozen_string_literal: true

# rubocop:disable Rails/SkipsModelValidations
# Converts main's data into the accounts-and-rules shape, then removes what main had and this
# schema does not. Runs inside the Migrator's transaction: any refused assertion rolls the whole
# run back. Migration-local table classes, so today's models never read yesterday's columns.
class AccountsAndRulesData < ActiveRecord::Migration[8.1]
  class Refused < StandardError; end

  EXPENSE = 0
  INCOME = 1
  SAVINGS = 2

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationAccount < ActiveRecord::Base
    self.table_name = "accounts"
  end

  class MigrationTransfer < ActiveRecord::Base
    self.table_name = "transfers"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  class MigrationItem < ActiveRecord::Base
    self.table_name = "items"
  end

  class MigrationEntry < ActiveRecord::Base
    self.table_name = "entries"
  end

  class MigrationRule < ActiveRecord::Base
    self.table_name = "rules"
  end

  class MigrationPool < ActiveRecord::Base
    self.table_name = "savings_pools"
  end

  def up
    stamp_days
    MigrationUser.order(:created_at, :id).each { |user| convert(user) }
    tighten
  end

  # Restores main's shape, not its rows: accounts, transfers and stamped dates stay, the dropped
  # columns and table come back empty. Enough to rebuild a development database.
  def down
    create_table :savings_pools, id: :uuid do |t|
      t.string :name, null: false
      t.money :target_amount, scale: 2
      t.date :start_date
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_reference :categories, :savings_pool, type: :uuid, foreign_key: true
    add_column :rules, :prorated, :boolean, null: false, default: false
    remove_check_constraint :categories, name: "categories_two_types"
    change_column_null :rules, :starts_on, true
    rename_column :entries, :date, :day
    # The rename carried date's NOT NULL onto day, which the schema migration left nullable.
    change_table :entries, bulk: true do |t|
      t.change_null :day, true
      t.column :date, :datetime
    end
    execute "UPDATE entries SET date = day::timestamp"
    change_column_null :entries, :date, false
  end

  private

  def now = @now ||= Time.current

  # Every entry's calendar day in its owner's timezone, before anything reads a date.
  def stamp_days
    execute <<~SQL.squish
      UPDATE entries
         SET day = (entries.date AT TIME ZONE 'UTC' AT TIME ZONE COALESCE(users.timezone, 'UTC'))::date
        FROM items, categories, users
       WHERE items.id = entries.item_id AND categories.id = items.category_id AND users.id = categories.user_id
    SQL
  end

  # The pools keep the names their owner chose; "Checking" is this migration's own invention, so it
  # is the name that yields when the two collide. Pool accounts are therefore minted first.
  def convert(user)
    truth = bank_truth(user)
    opened_on = opening_day(user)
    receipt = { accounts: 1, transfers: 0, entries: 0 }
    expected = Hash.new(0.to_d)
    pool_accounts = accounts_for_pools(user, opened_on, receipt)
    main = mint_account(user, "Checking", opened_on: opened_on)
    user.update_columns(main_account_id: main.id)
    convert_savings(user, main, pool_accounts, receipt, expected)
    MigrationCategory.where(user_id: user.id).update_all(savings_pool_id: nil, updated_at: now)
    receipt[:rules] = stamp_rules(user)
    verify!(user, truth, expected, main)
    announce_receipt(user, receipt)
  end

  def announce_receipt(user, receipt)
    say "#{user.email}: #{receipt[:accounts]} accounts, #{receipt[:transfers]} transfers from " \
        "#{receipt[:entries]} savings entries, #{receipt[:rules]} rules"
  end

  def accounts_for_pools(user, opened_on, receipt)
    first_days = first_savings_days(user)
    MigrationPool.where(user_id: user.id).order(:created_at, :id).to_h do |pool|
      receipt[:accounts] += 1
      [pool.id, mint_account(user, pool.name, opened_on: pool_opening(pool, first_days[pool.id], opened_on))]
    end
  end

  # An account opens no later than the first transfer it receives, whatever its pool's start date.
  def pool_opening(pool, first_day, fallback)
    [pool.start_date, first_day].compact.min || fallback
  end

  # The earliest day money reached each pool, by pool id. Read before any savings entry is deleted.
  def first_savings_days(user)
    entries_of(user)
      .where(categories: { category_type: SAVINGS })
      .where.not(categories: { savings_pool_id: nil })
      .group("categories.savings_pool_id")
      .minimum(:day)
  end

  def convert_savings(user, main, pool_accounts, receipt, expected)
    MigrationCategory.where(user_id: user.id, category_type: SAVINGS).order(:created_at, :id).each do |category|
      account = savings_account(user, category, pool_accounts, main, receipt)
      rows = entries_of_category(category).pluck(:amount, :day)
      move_savings(rows, main, account)
      expected[account.id] += rows.sum(0.to_d) { |amount, _day| amount.to_d }
      receipt[:transfers] += rows.size
      receipt[:entries] += delete_category(category)
    end
  end

  # A savings category lands in its pool's account, or in one minted under its own name.
  def savings_account(user, category, pool_accounts, main, receipt)
    pool_accounts[category.savings_pool_id] || begin
      receipt[:accounts] += 1
      mint_account(user, category.name, opened_on: main.opened_on)
    end
  end

  def mint_account(user, name, opened_on:)
    MigrationAccount.create!(
      user_id: user.id,
      name: unique_name(user, name),
      opening_balance: 0,
      opened_on: opened_on,
      created_at: now,
      updated_at: now
    )
  end

  def unique_name(user, base)
    taken = MigrationAccount.where(user_id: user.id).pluck(:name).to_set(&:downcase)
    return base unless taken.include?(base.downcase)

    suffix = 2
    suffix += 1 while taken.include?("#{base} #{suffix}".downcase)
    "#{base} #{suffix}"
  end

  def opening_day(user)
    first = entries_of(user).minimum(:day)
    first ? first - 1 : today_for(user)
  end

  def zone_of(user) = user.timezone.presence || "UTC"

  def today_for(user) = Time.current.in_time_zone(zone_of(user)).to_date

  def entries_of(user)
    MigrationEntry
      .joins("JOIN items ON items.id = entries.item_id JOIN categories ON categories.id = items.category_id")
      .where(categories: { user_id: user.id })
  end

  def entries_of_category(category)
    MigrationEntry.where(item_id: MigrationItem.where(category_id: category.id).select(:id))
  end

  def move_savings(rows, main, account)
    return if rows.empty?

    MigrationTransfer.insert_all!(
      rows.map do |amount, day|
        { from_account_id: main.id, to_account_id: account.id, amount: amount, date: day, created_at: now, updated_at: now }
      end
    )
  end

  def delete_category(category)
    deleted = entries_of_category(category).delete_all
    MigrationItem.where(category_id: category.id).delete_all
    category.delete
    deleted
  end

  def stamp_rules(user)
    rules = MigrationRule.where(category_id: MigrationCategory.where(user_id: user.id).select(:id))
    zone = zone_of(user)
    rules.find_each { |rule| rule.update_columns(starts_on: rule.created_at.in_time_zone(zone).to_date) }
    rules.count
  end

  def bank_truth(user)
    sum_of(user, INCOME) - sum_of(user, EXPENSE)
  end

  def sum_of(user, type) = entries_of(user).where(categories: { category_type: type }).sum(:amount).to_d

  def verify!(user, truth, expected, main)
    balances = balances_of(user, main)
    total = balances.values.sum(0.to_d)
    refuse(user, "accounts hold #{total} but the books said #{truth}") unless total == truth
    verify_savings!(user, expected, balances)
    refuse(user, "a savings category survived") if MigrationCategory.exists?(user_id: user.id, category_type: SAVINGS)
    unstarted = MigrationRule.where(category_id: MigrationCategory.where(user_id: user.id).select(:id), starts_on: nil)
    refuse(user, "a rule has no start") if unstarted.exists?
  end

  def verify_savings!(user, expected, balances)
    expected.each do |account_id, amount|
      held = balances.fetch(account_id, 0.to_d)
      refuse(user, "account #{account_id} holds #{held} but its savings summed to #{amount}") unless held == amount
    end
  end

  def balances_of(user, main)
    base = bank_truth(user)
    ids = MigrationAccount.where(user_id: user.id).pluck(:id)
    ins = transfer_sums(:to_account_id, ids)
    outs = transfer_sums(:from_account_id, ids)
    ids.to_h do |id|
      opening = id == main.id ? base : 0.to_d
      [id, opening + ins.fetch(id, 0).to_d - outs.fetch(id, 0).to_d]
    end
  end

  def transfer_sums(column, ids) = MigrationTransfer.where(column => ids).group(column).sum(:amount)

  def refuse(user, reason) = raise(Refused, "#{user.email}: #{reason}")

  def tighten
    remove_column :entries, :date
    rename_column :entries, :day, :date
    change_column_null :entries, :date, false
    change_column_null :rules, :starts_on, false
    remove_column :rules, :prorated
    remove_reference :categories, :savings_pool, type: :uuid, foreign_key: true, index: true
    drop_table :savings_pools
    add_check_constraint :categories, "category_type IN (0, 1)", name: "categories_two_types"
  end
end
# rubocop:enable Rails/SkipsModelValidations
