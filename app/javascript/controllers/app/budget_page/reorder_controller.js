import { Controller } from "@hotwired/stimulus"

// Dragging the Budget page's category cards into a new fill order. Progressive enhancement
// only: the ▲▼ buttons beside each card already submit the same PATCH with the same
// `category_ids[]` shape, so with scripting off the order is still reachable and nothing here is
// load-bearing.
//
// The cards are reordered in the DOM as the pointer moves and the new order is read back off
// them at drop, so there is one description of "the order" — where the cards actually are —
// rather than an index this controller keeps beside them and could get wrong.
//
// A CANCELLED DRAG PUTS THE CARDS BACK. `dragend` fires whether the user dropped or pressed
// Escape / released outside the band, and the DOM has already been rearranged by then — so
// submitting on `dragend` alone writes an order the user explicitly abandoned. `drop` is the
// only event that means "yes, here", so it is what arms the submit; without it `#restore` walks
// the cards back to the order recorded at `dragstart`.
export default class extends Controller {
  static targets = ["row", "form"]

  start(event) {
    this.dragged = event.currentTarget
    this.orderBefore = this.categoryIds
    // WHERE EACH CARD WAS, not just what order the cards were in — see `#restore`.
    this.placeBefore = this.rowTargets.map((row) => [row, row.nextSibling])
    this.dropped = false
    event.dataTransfer.effectAllowed = "move"
    // Firefox will not begin a drag whose dataTransfer carries nothing.
    event.dataTransfer.setData("text/plain", this.dragged.dataset.categoryId)
    this.dragged.classList.add("opacity-50")
  }

  // Bound on the list rather than on each card, so the gaps between cards are drop targets too
  // and `preventDefault` covers the whole list — a drag released over a gap is a drop, not a
  // cancel.
  over(event) {
    if (!this.dragged) return

    // preventDefault is what marks this a valid drop target; without it the card springs back
    // and `drop` never fires.
    event.preventDefault()
    const row = event.target.closest("[data-app--budget-page--reorder-target='row']")
    if (!row || row === this.dragged) return

    const midpoint = row.getBoundingClientRect().top + row.offsetHeight / 2
    this.element.insertBefore(this.dragged, event.clientY < midpoint ? row : row.nextElementSibling)
  }

  drop(event) {
    event.preventDefault()
    this.dropped = true
  }

  finish() {
    if (!this.dragged) return

    this.dragged.classList.remove("opacity-50")
    this.dragged = null
    if (!this.dropped) return this.restore()
    // A drag that ended where it started is not a reorder, and a PATCH that rewrites the order
    // it already holds would still cost the user a page load and a flash message.
    if (this.categoryIds.join() !== this.orderBefore.join()) this.submit()
  }

  // Back to where each card was at `dragstart` — its own recorded `nextSibling`, not "before the
  // form".
  //
  // The old spelling re-inserted every row target before the hidden form in turn, which puts the
  // cards back in the right order relative to EACH OTHER and moves anything that is not a row target
  // out from between them: the list holds more than draggable cards (a ruled category that no longer
  // holds money renders a band rather than a card, and it is not a `row` target), so a cancelled
  // drag left the page visibly rearranged in a way no drop had asked for and no PATCH recorded.
  // Restoring to the recorded siblings puts every child back, targets and non-targets alike.
  //
  // WALKED IN REVERSE, because a recorded sibling must already be in place before the card that
  // goes in front of it moves. Only `this.dragged` has actually moved, so by the time the walk
  // reaches it every later card is where it was.
  restore() {
    for (let index = this.placeBefore.length - 1; index >= 0; index--) {
      const [row, next] = this.placeBefore[index]
      this.element.insertBefore(row, next)
    }
  }

  // THE DOM ORDER IS THE WIRE ORDER. The list is drawn in PRIORITY order — the key
  // `Category.apply_fill_order` writes, position 0 meaning `priority: 0` — so where the cards are IS
  // the order, with nothing in between to get wrong. (A reversal stood here for one commit, while
  // the list was drawn in give-way order; see `BudgetPageHelper#reordered_category_ids` for why that
  // list could not be dragged at all.)
  submit() {
    const form = this.formTarget
    form.querySelectorAll("input[name='category_ids[]']").forEach((input) => input.remove())
    this.categoryIds.forEach((id) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "category_ids[]"
      input.value = id
      form.appendChild(input)
    })
    form.requestSubmit()
  }

  rowFor(id) {
    return this.rowTargets.find((row) => row.dataset.categoryId === id)
  }

  get categoryIds() {
    return this.rowTargets.map((row) => row.dataset.categoryId)
  }
}
