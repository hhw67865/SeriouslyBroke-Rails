# frozen_string_literal: true

class CreatePoolMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :pool_movements, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :from_pool, type: :uuid, null: false, foreign_key: { to_table: :pools }
      t.references :to_pool, type: :uuid, null: false, foreign_key: { to_table: :pools }
      t.references :source_entry, type: :uuid, null: true, foreign_key: { to_table: :entries }
      t.money :amount, scale: 2, null: false
      t.datetime :date, null: false
      t.timestamps
    end

    add_index :pool_movements, :date
  end
end
