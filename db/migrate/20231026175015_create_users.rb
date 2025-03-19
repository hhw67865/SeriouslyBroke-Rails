class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :clerk_user_id

      t.timestamps
    end
  end
end
