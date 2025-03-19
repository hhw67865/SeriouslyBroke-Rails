class MigrateClerkUsersToDevise < ActiveRecord::Migration[7.1]
  def up
    # Update users with clerk_user_id that don't have devise credentials yet
    User.where.not(clerk_user_id: nil).find_each do |user|
      # Skip users that already have devise credentials
      next if user.attributes['email'].present? && user.attributes['encrypted_password'].present?
      
      # Generate unique email based on clerk_user_id to avoid conflicts
      temp_email = "user_#{user.clerk_user_id}@seriouslybroke.com"
      temp_password = "ChangeMe123!#{SecureRandom.hex(4)}" # Make password unique per user
      
      # Update the user with temporary credentials
      user.update_columns(
        email: temp_email,
        encrypted_password: ::User.new.send(:password_digest, temp_password)
      )
      
      # Output the credentials so they can be saved
      puts "\n================================================="
      puts "Temporary credentials for user #{user.clerk_user_id}:"
      puts "Email: #{temp_email}"
      puts "Password: #{temp_password}"
      puts "=================================================\n"
    end

    # Verify all users have required Devise fields
    missing_credentials = User.where("email IS NULL OR encrypted_password IS NULL OR encrypted_password = ''")
    if missing_credentials.exists?
      raise "Some users are missing required Devise fields after migration"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
