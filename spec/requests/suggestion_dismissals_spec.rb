# frozen_string_literal: true

require "rails_helper"

# HIDING A SUGGESTION, AT THE WIRE (Henry's ruling of 2026-08-20). This route REVERSES §8's
# recorded no-dismissal design — the argument the spec made against it, and the ruling that
# overrode it, are written down in `app/views/budget_page/_suggestions.html.erb` where the panel
# itself is.
#
# A REQUEST SPEC because the questions here are ones the browser cannot ask: a `subject_id` that
# belongs to somebody else, a `subject_type` no suggestion has ever carried, and a dismissal row
# written by one user reaching another user's panel. The browser path — hide it, reload, show it
# again — is in spec/system/budget_page/suggestions_spec.rb.
RSpec.describe "Suggestion dismissals", type: :request do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400) }
  let(:stranger) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:utilities) { create(:category, :expense, user: user, name: "Utilities", pool: checking) }
  let(:phone) { create(:item, category: utilities, name: "Phone") }

  # TWO PAYMENTS A WHOLE MONTH APART: the measured dated-bill shape, the same one the system spec
  # plants. The history is planted rather than the engine stubbed, for the reason that file gives.
  before do
    user.update!(default_account: checking)
    create(:entry, item: phone, amount: 85, date: Date.current - 2.months)
    create(:entry, item: phone, amount: 85, date: Date.current - 1.month)
    sign_in user, scope: :user
  end

  def hide(params) = post(suggestion_dismissals_path, params: params)

  def own_suggestion = { kind: "dated_bill", subject_type: "Item", subject_id: phone.id }

  def panel_holds_phone? = response.body.include?(%(data-suggestion="dated_bill:#{phone.id}"))

  describe "POST /suggestion_dismissals", :aggregate_failures do
    # THE REACH DIRECTION FIRST: without it every refusal below would pass just as well against a
    # route that hid nothing at all.
    it "writes the dismissal, sends the user back to the page, and takes the row off it" do
      expect { hide(own_suggestion) }.to change(SuggestionDismissal, :count).by(1)
      expect(response).to redirect_to(budget_page_path)

      get budget_page_path
      expect(panel_holds_phone?).to be false
    end

    # §7a'S OWNERSHIP CLASS, on a new wire parameter: `subject_id` names a record the panel is
    # about, and unscoped it would let a stranger's item be looked up — and its NAME rendered back
    # in this user's hidden list, which is the read-shaped half of the same leak. Scoped through
    # `current_user`, so a stranger's id is not found rather than found and refused.
    it "refuses a stranger's subject and writes nothing" do
      foreign = create(:item, category: create(:category, :expense, user: stranger))

      expect { hide(kind: "dated_bill", subject_type: "Item", subject_id: foreign.id) }
        .not_to change(SuggestionDismissal, :count)
      expect(response).to have_http_status(:not_found)
    end

    # A `subject_type` IS A CLASS NAME OFF THE WIRE, and constantizing one is how a polymorphic
    # association becomes a remote-code hazard. Only the three classes a suggestion's subject can
    # actually be are answerable; anything else is refused before a lookup happens at all.
    it "refuses a subject_type no suggestion carries" do
      expect { hide(kind: "dated_bill", subject_type: "User", subject_id: stranger.id) }
        .not_to change(SuggestionDismissal, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a kind no detector produces" do
      expect { hide(own_suggestion.merge(kind: "everything")) }.not_to change(SuggestionDismissal, :count)
      expect(response).to redirect_to(budget_page_path)
    end

    # A DOUBLE SUBMIT IS NOT A CRASH. The unique index is the real guard, and the validation in
    # front of it means the second click reaches a redirect rather than `RecordNotUnique`.
    it "survives the same suggestion being hidden twice" do
      hide(own_suggestion)

      expect { hide(own_suggestion) }.not_to change(SuggestionDismissal, :count)
      expect(response).to redirect_to(budget_page_path)
    end
  end

  describe "DELETE /suggestion_dismissals/:id", :aggregate_failures do
    it "puts the suggestion back on the page" do
      hide(own_suggestion)
      dismissal = user.suggestion_dismissals.sole

      expect { delete suggestion_dismissal_path(dismissal) }.to change(SuggestionDismissal, :count).by(-1)
      expect(response).to redirect_to(budget_page_path)

      get budget_page_path
      expect(panel_holds_phone?).to be true
    end

    it "refuses a stranger's dismissal" do
      foreign_item = create(:item, category: create(:category, :expense, user: stranger))
      dismissal = SuggestionDismissal.create!(user: stranger, subject: foreign_item, kind: "dated_bill")

      expect { delete suggestion_dismissal_path(dismissal) }.not_to change(SuggestionDismissal, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  # A DISMISSAL IS ONE USER'S, and this is the pin that says the engine's lookup is scoped by the
  # owner rather than by the (kind, subject) pair alone. The row planted here is one the wire
  # cannot make — the stranger's dismissal naming THIS user's item — precisely so that a filter
  # keyed on anything but `user_id` shows up as this user's own suggestion vanishing.
  it "never hides a suggestion for the user who did not hide it", :aggregate_failures do
    SuggestionDismissal.create!(user: stranger, subject: phone, kind: "dated_bill")

    get budget_page_path

    expect(panel_holds_phone?).to be true
  end
end
