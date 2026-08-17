# frozen_string_literal: true

require "rails_helper"

# THE DECLARATION'S PARAMETER BOUNDARY. `PATCH /budget/user` writes the signed-in user's own row,
# so ownership is never the question here — the permitted list is, and it is the whole of the
# question: `User` carries `email`, `encrypted_password`, `theme` and `default_account_id` on the
# same record as the three fields this form owns.
#
# A request spec rather than a system spec, because a browser cannot submit a field the form does
# not render. The refusal is a fact about the route.
RSpec.describe "Budget page declaration", type: :request do
  let(:user) { create(:user, theme: :light) }

  before { sign_in user, scope: :user }

  def declare(params) = patch(budget_page_user_path, params: { user: params })

  describe "the three permitted params", :aggregate_failures do
    it "writes all three and comes back to the page" do
      declare(typical_income: "2400", period_cadence: "biweekly", period_anchor_date: "2026-02-06")

      expect(response).to redirect_to(budget_page_path)
      expect(user.reload).to have_attributes(
        typical_income: BigDecimal("2400"),
        period_cadence: "biweekly",
        period_anchor_date: Date.new(2026, 2, 6)
      )
    end

    # Clearing the period back to undeclared is a legitimate move — the form offers a blank
    # option — and the income survives it, because income is untethered from the period (§3).
    it "lets the period be cleared without clearing the income" do
      user.update!(typical_income: 2_400, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6))

      declare(typical_income: "2400", period_cadence: "", period_anchor_date: "")

      expect(user.reload.period_cadence).to be_nil
      expect(user.reload.typical_income).to eq(2_400)
    end
  end

  # A FOURTH PARAM IS REFUSED — dropped by the permitted list, not written. Asserted on `theme`
  # because it is a real column with a real writer elsewhere in the app, so a widened list would
  # show up here as a value that actually changed rather than as a no-op.
  describe "a fourth param", :aggregate_failures do
    it "is not written, while the permitted three are" do
      declare(
        typical_income: "2400",
        period_cadence: "monthly",
        period_anchor_date: "2026-02-01",
        theme: "dark"
      )

      expect(user.reload.theme).to eq("light")
      expect(user.reload.typical_income).to eq(2_400)
    end

    # The pair: `email` is what a mass-assignment attack would actually reach for, and unlike
    # `theme` a changed one locks the owner out of their own account.
    it "cannot rewrite the email the session is signed in as" do
      original = user.email

      declare(typical_income: "2400", email: "attacker@example.com")

      expect(user.reload.email).to eq(original)
    end
  end

  # A CADENCE WITH NO ANCHOR yields no boundaries at all, so every divisor downstream falls back
  # to its `[count, 1].max` clamp and the app demands whole bills out of one period. `User`
  # refuses it; this pins that the refusal arrives as a 422 the page can render rather than as a
  # 500 or a silent partial write.
  describe "an invalid declaration", :aggregate_failures do
    it "renders the page again with the error and persists nothing" do
      declare(typical_income: "2400", period_cadence: "biweekly", period_anchor_date: "")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Period anchor date is required when you set a period")
      expect(user.reload.typical_income).to be_nil
      expect(user.reload.period_cadence).to be_nil
    end

    it "refuses a zero income and keeps the previous one" do
      user.update!(typical_income: 2_400)

      declare(typical_income: "0")

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.typical_income).to eq(2_400)
    end
  end

  describe "a signed-out request", :aggregate_failures do
    it "is sent to sign in rather than writing anything" do
      sign_out user

      declare(typical_income: "9999")

      expect(response).to redirect_to(new_user_session_path)
      expect(user.reload.typical_income).to be_nil
    end
  end
end
