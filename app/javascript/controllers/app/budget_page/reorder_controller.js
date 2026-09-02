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

  // Back to the order recorded at `dragstart`. Each card is re-inserted before the hidden form,
  // which is the list's last child — so the header stays first, the form stays last, and the
  // cards land between them in the order they were in.
  restore() {
    this.orderBefore.forEach((id) => this.element.insertBefore(this.rowFor(id), this.formTarget))
  }

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
