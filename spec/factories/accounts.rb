# frozen_string_literal: true

FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "#{Faker::Bank.name} #{n}" }
    opening_balance { 0 }
    association :user

    # The first account a user gets is main, the rule Account.open applies. update_columns so a
    # :js example's request thread never races this write through has_many autosave validation.
    after(:create) do |account|
      if account.user.main_account_id.blank?
        account.user.update_columns(main_account_id: account.id) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    trait :savings do
      before(:create) { |account| create(:account, user: account.user) if account.user.main_account_id.blank? }
    end
  end
end
