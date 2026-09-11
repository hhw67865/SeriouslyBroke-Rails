# frozen_string_literal: true

require "rails_helper"

# The account form: name and balance as before, then what the account is owed as a list of rows,
# each a fixed amount or a share of an income item, and the keeps-extra choice.
RSpec.describe "Account edit", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:emergency) { create(:account, user: user, name: "Emergency", opening_balance: 500) }
  let(:paycheck) { Item.find_by!(name: "Paycheck") }

  around { |example| travel_to(today) { example.run } }

  # Checking is created first, so `Account.open` makes it main; forcing `emergency` here (rather
  # than a `let!`) keeps it created in that same order, right after checking.
  before do
    create(:account, user: user, name: "Checking", opening_balance: 4_000)
    create(:item, :income, user: user, name: "Paycheck")
    sign_in user, scope: :user
    emergency
  end

  context "with no target yet" do
    before { visit edit_account_path(emergency) }

    it "saves a fixed target and the mode without JavaScript", :aggregate_failures do
      within("[data-target-row]", match: :first) do
        select "A fixed amount", from: "Source"
        fill_in "A period", with: "200"
        fill_in "Since", with: "2026-09-04"
      end
      choose "Ask every period"
      click_button "Save account"

      expect(page).to have_content("Emergency updated.")
      expect(page).to have_css("[data-account-targets]", text: "$200.00 a period")
      expect(emergency.reload).not_to be_keeps_extra
    end

    it "refuses a share past 100% and keeps the typed rows", :aggregate_failures do
      within("[data-target-row]", match: :first) do
        select "Paycheck", from: "Source"
        fill_in "Share", with: "150"
      end
      click_button "Save account"

      expect(page).to have_content("would take Paycheck past 100%")
      expect(page).to have_field("Share", with: "150")
    end

    # Regression: the index value used to be read from `@account.savings_targets.size` before the
    # placeholder row was built, so on a fresh account it was 0 — the same child index the
    # placeholder itself renders at. "Add another" then produced a second row also indexed 0,
    # Rack merged the two under one key, and the fixed row vanished with no error.
    context "with the placeholder row filled" do
      before do
        within("[data-target-row]", match: :first) do
          select "A fixed amount", from: "Source"
          fill_in "A period", with: "200"
        end
      end

      it "adds a share row without colliding on index 0", :aggregate_failures, :js do
        click_button "Add another"
        within(all("[data-target-row]").last) do
          select "Paycheck", from: "Source"
          fill_in "Share", with: "10"
        end
        click_button "Save account"

        expect(page).to have_css("[data-account-targets]", text: "$200.00 a period, plus 10% of Paycheck")
        expect(emergency.savings_targets.reload.count).to eq(2)
      end
    end
  end

  context "with an existing fixed target", :js do
    before { create(:savings_target, account: emergency, amount: 200) }

    it "adds a share row and switches the figure field with the source", :aggregate_failures do
      visit edit_account_path(emergency)

      click_button "Add another"
      within(all("[data-target-row]").last) do
        select "Paycheck", from: "Source"
        expect(page).to have_field("Share")
        expect(page).to have_no_field("A period")
        fill_in "Share", with: "10"
      end
      click_button "Save account"

      expect(page).to have_css("[data-account-targets]", text: "$200.00 a period, plus 10% of Paycheck")
    end

    it "removes a row", :aggregate_failures do
      create(:savings_target, :share, account: emergency, item: paycheck, percent: 10)
      visit edit_account_path(emergency)

      within("[data-target-row]", match: :first) { click_button "Remove" }
      click_button "Save account"

      expect(page).to have_css("[data-account-targets]", text: "10% of Paycheck")
      expect(emergency.savings_targets.reload.map(&:words)).to eq(["10% of Paycheck"])
    end
  end

  it "shows what percent of typical income a fixed amount is", :aggregate_failures do
    salary = create(:category, :income, user: user)
    [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each { |on| create(:entry, item: create(:item, category: salary), amount: 2_000, date: on) }
    create(:savings_target, account: emergency, amount: 200)

    visit edit_account_path(emergency)

    expect(page).to have_css("[data-target-hint]", text: "That's 10% of what you typically bring in.")
  end
end
