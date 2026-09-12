# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings" do
  let(:user) { create(:user, :biweekly) }

  before do
    create(:account, user: user, name: "Checking")
    sign_in user, scope: :user
  end

  it "renders the page with checking and the savings accounts", :aggregate_failures do
    create(:account, user: user, name: "Emergency")

    get savings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Spending account").and include("Emergency")
  end

  it "renders an empty state for a user with no accounts yet", :aggregate_failures do
    fresh_user = create(:user, :biweekly)
    sign_in fresh_user, scope: :user

    get savings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "Open your first account. It becomes your checking account, where income lands and everything is claimed from."
    )
  end
end
