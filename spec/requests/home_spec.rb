# frozen_string_literal: true

require "rails_helper"

# HIGH-1 (fix round 2, main-account spec §5): `users.default_account_id` nullifies when the
# main account is deleted (`add_foreign_key :users, :pools, column: :default_account_id,
# on_delete: :nullify`), and the fund-account card used to read `main_account.name`
# unconditionally — a user left with no main account 500'd on Home with no door back in.
# `HomePresenter#awaiting_funding?` now requires a main account before it offers the card to
# anyone at all, which is what this pins: a request-spec status code, because Capybara's
# Selenium driver cannot see one.
RSpec.describe "Home", type: :request do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:ally) { create(:pool, :account, user: user, name: "Ally") }

  before { sign_in user, scope: :user }

  it "renders with no funding card, and the add-account door, when there is no main account", :aggregate_failures do
    user.update!(default_account: nil)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(checking.name, ally.name)
    expect(response.body).not_to include("Real balance today")
    expect(response.body).to include("Add a bank account")
  end
end
