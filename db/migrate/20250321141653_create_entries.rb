class CreateEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :entries, id: :uuid do |t|
      t.money :amount, null: false
      t.datetime :date, null: false
      t.text :description
      t.references :item, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
