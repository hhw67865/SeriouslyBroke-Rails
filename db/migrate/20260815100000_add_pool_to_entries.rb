# frozen_string_literal: true

class AddPoolToEntries < ActiveRecord::Migration[8.1]
  def change
    add_reference :entries, :pool, type: :uuid, foreign_key: true, null: true
  end
end
