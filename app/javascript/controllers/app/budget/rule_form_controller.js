import { Controller } from "@hotwired/stimulus"

// THE RULES FORM'S REVEALS (rules-own-the-budget spec §4).
//
// Two jobs, and neither of them is a gate. The server renders every control with the `hidden` state
// the current choice implies and validates whatever comes back, so a browser with no JavaScript
// gets the whole form (the partial's `<noscript>` rule forces the blocks visible) and a legible 422
// if the answers do not hang together. What this adds is that the form follows the radios:
//
//   * "Pays" lists EVERY item the user owns, each stamped with its own category, and the ones that
//     belong to some other category are hidden as the category changes. Filtering here rather than
//     re-fetching is what makes the category select feel immediate.
//   * "every N months" reveals the interval and the date, "once" reveals the date, "builds up"
//     reveals the target, and the dated schedules hide "Unspent money" entirely — a dated rule's
//     build-up is defined by its date, and `Budget#build_up_must_be_valid` refuses the pair.
//
// ** A HIDDEN FIELD IS CLEARED, AND ITS VALUE IS PUT BACK WHEN IT RETURNS. ** A hidden input still
// submits, so a user who typed a due date and then chose "per period" would send a date the form no
// longer shows — and `RuleForm` refuses a due date on a per-period rule rather than laundering it
// away, so the refusal would be about a control that is not on screen. Stashing on the element
// keeps a toggle back and forth from costing the user their typing.
export default class extends Controller {
  static targets = [
    "category",
    "item",
    "intervalField",
    "anchorField",
    "unspentField",
    "targetField"
  ]

  // THE OWNER, WHERE NO INPUT CARRIES IT. On an EDIT the category is read-only and the form submits
  // nothing for it (fix round 1 - M1), so the value on the form element is the only statement of
  // which category "Pays" should be filtered by.
  static values = { category: String }

  connect() {
    this.refresh()
  }

  refresh() {
    this.filterItems()
    this.revealFields()
  }

  // The category in force: the picker's selection while the user is choosing, and otherwise the one
  // the form was rendered for. The target wins because it is the live one.
  get categoryId() {
    return this.hasCategoryTarget ? this.categoryTarget.value : this.categoryValue
  }

  get schedule() {
    const checked = this.element.querySelector('input[name="budget[schedule]"]:checked')
    return checked ? checked.value : "per_period"
  }

  get unspent() {
    const checked = this.element.querySelector('input[name="budget[unspent]"]:checked')
    return checked ? checked.value : "resets"
  }

  filterItems() {
    if (!this.hasItemTarget) return

    const categoryId = this.categoryId

    this.itemTarget.querySelectorAll("option[data-category-id]").forEach((option) => {
      const belongs = option.dataset.categoryId === categoryId
      option.hidden = !belongs
      option.disabled = !belongs
    })

    // An item left selected under a category it does not belong to would submit a pairing
    // `Budget#item_must_belong_to_category` refuses; "the whole category" is the default anyway.
    const selected = this.itemTarget.selectedOptions[0]
    if (selected && selected.disabled) this.itemTarget.value = ""
  }

  revealFields() {
    const dateless = this.schedule === "per_period" || this.schedule === "monthly"

    this.toggle(this.intervalFieldTarget_, this.schedule === "every_n")
    this.toggle(this.anchorFieldTarget_, this.schedule === "every_n" || this.schedule === "once")
    this.toggle(this.unspentFieldTarget_, dateless)
    this.toggle(this.targetFieldTarget_, dateless && this.unspent === "builds")

    // ** THE SAME REFUSAL THE SERVER RENDERS (fix round 1 - L2). ** A dated rule cannot carry money
    // over at all, so its "Unspent money" radios and the Target below them are DISABLED as well as
    // away - the state a browser with no JavaScript is served, and the one this has to keep in step
    // with as the schedule moves. Disabled is not the same question as hidden: the Target is hidden
    // under "Resets each period" and still enabled, because moving the radio one line up is how a
    // JavaScript-less user reaches it.
    this.setDisabled(this.unspentFieldTarget_, !dateless)
    this.setDisabled(this.targetFieldTarget_, !dateless)
  }

  setDisabled(field, disabled) {
    if (!field) return

    field.querySelectorAll("input").forEach((input) => {
      input.disabled = disabled
    })
  }

  get intervalFieldTarget_() {
    return this.hasIntervalFieldTarget ? this.intervalFieldTarget : null
  }

  get anchorFieldTarget_() {
    return this.hasAnchorFieldTarget ? this.anchorFieldTarget : null
  }

  get unspentFieldTarget_() {
    return this.hasUnspentFieldTarget ? this.unspentFieldTarget : null
  }

  get targetFieldTarget_() {
    return this.hasTargetFieldTarget ? this.targetFieldTarget : null
  }

  // Nothing happens when the state already matches, which is what keeps `connect()` from clearing a
  // prefilled date on a form the server rendered correctly in the first place.
  toggle(field, visible) {
    if (!field || field.hidden === !visible) return

    field.hidden = !visible
    // RADIOS ARE LEFT ALONE. A radio's `value` is what it MEANS, not what somebody typed, so
    // blanking one submits an empty choice rather than an untouched one.
    const typed = "input:not([type=radio]):not([type=checkbox]):not([type=hidden])"
    field.querySelectorAll(typed).forEach((input) => {
      if (visible) {
        if (input.dataset.stashedValue !== undefined) {
          input.value = input.dataset.stashedValue
          delete input.dataset.stashedValue
        }
      } else {
        input.dataset.stashedValue = input.value
        input.value = ""
      }
    })
  }
}
