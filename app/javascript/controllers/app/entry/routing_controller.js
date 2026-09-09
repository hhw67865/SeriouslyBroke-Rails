import { Controller } from "@hotwired/stimulus"

// THE §4 "Lands in" SELECT'S LIVE HALF: income is asked which account it arrived in, and nothing
// else is.
//
// THE WHOLE CONTROLLER IS ONE TOGGLE, deliberately. Everything about the field — its options, its
// selected account, its label — is rendered by the server on the way down and never touched here;
// the only thing the browser knows that the server does not is which category the user has picked
// SINCE the page loaded, so that is the only question this answers.
//
// THE INCOME IDS COME DOWN FROM THE SERVER rather than being read off the category select's
// optgroup labels. "Incomes" is a `.titleize.pluralize` of an enum name meant for a human to read,
// and matching on it would make a display string load-bearing — rename the group and the select
// silently stops appearing. The ids are the same list the select was built from.
//
// ONE CATEGORY-CHANGE HOOK IN THE FORM. `app--entry--form` announces `entry:categoryChanged` and
// this listens for it, exactly as `app--entry--impact` does — a second listener on the select
// itself would be a second description of "the user picked a category", free to disagree with the
// first about when that happened.
export default class extends Controller {
  static targets = ["field"]
  static values = { incomeIds: Array }

  categoryChanged(event) {
    this.fieldTarget.hidden = !this.incomeIdsValue.includes(event.detail.categoryId)
  }
}
