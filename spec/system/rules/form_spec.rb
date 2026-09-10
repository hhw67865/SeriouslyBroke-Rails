# frozen_string_literal: true

require "rails_helper"

# The rule form: one category, three steps, and a preview card the SERVER renders.
#
# The reveals are an enhancement, not a gate. Each conditional block is rendered with the `hidden`
# state the current choice implies, so a Rack::Test example reaches a dated rule's controls by
# opening the form on that schedule — the same door a prefilled link comes through — and the
# controller is only asked for where the point is the browser keeping up with the typing.
RSpec.describe "Rule form", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  around { |example| travel_to(today) { example.run } }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
  end

  def open_form(**prefill) = visit new_rule_path(category_id: groceries.id, **prefill)

  def written = groceries.rules.sole

  # Step 1 and step 3 are the whole of a per-period rule: how much, and what kind. The date the rule
  # starts counting from is offered beside the amount, because spending before it belongs to whatever
  # the user was doing before they wrote the rule.
  it "writes a per-period allowance and opens its category", :aggregate_failures do
    open_form

    expect(page).to have_content("New rule for Groceries")
    fill_in "Amount", with: "400"
    fill_in "Counts from", with: "2026-09-04"
    choose "Usage"
    click_button "Create rule"

    expect(page).to have_content("Rule was successfully created.")
    expect(page).to have_css("[data-category-panel='Groceries']")
    expect(written).to have_attributes(amount: 400, rule_type: "usage", anchor_date: nil)
    expect(written.starts_on).to eq(Date.new(2026, 9, 4))
  end

  # "Keeps what it doesn't spend" is a detail OF "Every period" and not a third option: the money
  # still arrives every period, and the only question is what the boundary does to what is left.
  it "writes an allowance that keeps what it doesn't spend", :aggregate_failures do
    open_form

    fill_in "Amount", with: "60"
    check "Keeps what it doesn't spend"
    choose "Usage"
    click_button "Create rule"

    expect(page).to have_content("Rule was successfully created.")
    expect(written).to have_attributes(keeps_unspent: true, anchor_date: nil)
  end

  # "By a date" is money saved up toward a day — a bill or a goal, which are one shape — and it is
  # the schedule that reveals the due date.
  it "writes a dated bill on the schedule that asks for a date", :aggregate_failures do
    open_form(rule: { schedule: "by_date" })

    fill_in "Amount", with: "900"
    fill_in "Due", with: "2026-10-16"
    choose "Bill"
    click_button "Create rule"

    expect(page).to have_content("Rule was successfully created.")
    expect(written).to have_attributes(amount: 900, rule_type: "bill", interval_months: nil)
    expect(written.anchor_date).to eq(Date.new(2026, 10, 16))
  end

  # Repeating is a detail OF "by a date": the interval is revealed by the checkbox, not by a third
  # schedule of its own.
  it "writes a rolling bill when the repeat box is ticked", :aggregate_failures do
    open_form(rule: { schedule: "by_date", repeats: "1" })

    fill_in "Amount", with: "600"
    fill_in "Due", with: "2026-10-01"
    fill_in "Comes round every (months)", with: "6"
    choose "Bill"
    click_button "Create rule"

    expect(page).to have_content("Rule was successfully created.")
    expect(written).to have_attributes(interval_months: 6, anchor_date: Date.new(2026, 10, 1))
  end

  # The refusal lands under the control that caused it, and what the user typed is still in the box.
  it "refuses an amount that is not money and says so on the field", :aggregate_failures do
    open_form

    fill_in "Amount", with: "0"
    choose "Usage"
    click_button "Create rule"

    expect(page).to have_content("must be greater than 0")
    expect(page).to have_field("Amount", with: "0")
    expect(groceries.rules).to be_empty
  end

  # An edit offers every control the new form does, and it opens on the rule's own answers.
  it "edits a rule from the page it is listed on", :aggregate_failures do
    rule = create(:rule, :rate, category: groceries, amount: 400, starts_on: Date.new(2026, 1, 1))

    visit edit_rule_path(rule)

    expect(page).to have_field("Amount", with: "400.0")
    fill_in "Amount", with: "450"
    click_button "Update rule"

    expect(page).to have_content("Rule was successfully updated.")
    expect(rule.reload.amount).to eq(450)
  end

  # Step 1's select became a history table: one row per item, an "everything else" row, and a row
  # that names a new item.
  describe "the item picker" do
    let!(:bread) { create(:item, category: groceries, name: "Bread") }

    it "shows an item's history and checks everything else by default", :aggregate_failures do
      # On a period's own opening day, so the walk counts it as a whole complete period.
      create(:entry, item: bread, amount: 12, date: Date.new(2026, 7, 24))

      open_form

      expect(page).to have_css("label", text: "Bread")
      expect(page).to have_field("rule_item_everything", checked: true)
      expect(page).to have_content("12.00")
    end

    it "disables a ruled item's radio and tags it", :aggregate_failures do
      create(:rule, :rate, category: groceries, item: bread, amount: 50, starts_on: Date.new(2026, 1, 1))

      open_form

      expect(page).to have_field("rule_item_#{bread.id}", disabled: true)
      expect(page).to have_content("has its own rule · Usage")
    end

    it "writes the rule for the item picked", :aggregate_failures do
      open_form

      choose "rule_item_#{bread.id}"
      fill_in "Amount", with: "40"
      choose "Usage"
      click_button "Create rule"

      expect(page).to have_content("Rule was successfully created.")
      expect(written.item).to eq(bread)
    end

    it "names a new item and creates it along with the rule", :aggregate_failures do
      open_form

      choose "rule_item_new"
      fill_in "rule_new_item_name", with: "Cereal"
      fill_in "Amount", with: "40"
      choose "Usage"
      click_button "Create rule"

      expect(page).to have_content("Rule was successfully created.")
      expect(written.item.name).to eq("Cereal")
      expect(groceries.items.pluck(:name)).to include("Cereal")
    end

    it "names the sentence's subject after the chosen row", :aggregate_failures, :js do
      open_form

      expect(page).to have_css("[data-app--budget--rule-form-target='subjectName']", text: "Everything else in Groceries")

      choose "rule_item_#{bread.id}"

      expect(page).to have_css("[data-app--budget--rule-form-target='subjectName']", text: "Bread")
    end
  end

  # The card is the server's, refreshed into a Turbo Frame as the blanks change, and it exists only
  # where the controller runs — the frame is rendered `hidden` and `connect()` is what lifts it.
  describe "the preview card", :js do
    it "says the rule back as it is typed", :aggregate_failures do
      open_form

      expect(page).to have_css("[data-preview-missing]", text: "Fill in an amount.")

      fill_in "Amount", with: "400"
      choose "Usage"

      expect(page).to have_css("[data-preview-sentence]", text: "Groceries gets $400.00 every period")
      expect(page).to have_css("[data-preview-figure='per_period']", text: "$400.00")
      expect(page).to have_css("[data-preview-type]", text: "It's usage, so it gives way after your choices")
    end

    # Choosing "By a date" reveals the day the money is wanted, and the card re-prices the rule on
    # it: $900 by Oct 16 is four periods' worth of saving on this grid.
    it "reveals the date and re-prices the rule on it", :aggregate_failures do
      open_form

      fill_in "Amount", with: "900"
      choose "By a date"
      # A Date rather than a string: a real date input is typed in the browser's own field order, so
      # "2026-10-16" lands as a year in the month box.
      fill_in "Due", with: Date.new(2026, 10, 16)
      choose "Bill"

      expect(page).to have_css("[data-preview-sentence]", text: "Groceries gets $900.00 by Oct 16, 2026")
      expect(page).to have_css("[data-preview-figure='per_period']", text: "$225.00")
      expect(page).to have_css("[data-preview-figure='periods_left']", text: "4")
    end
  end
end
