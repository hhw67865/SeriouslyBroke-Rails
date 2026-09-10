import { Controller } from "@hotwired/stimulus"

// Dragging the cards into a new order. Enhancement only — the ▲▼ buttons write the same list — and
// `drop` is the only event that arms the submit, so a cancelled drag puts the cards back.
export default class extends Controller {
  static targets = ["row", "form"]

  start(event) {
    this.dragged = event.currentTarget
    this.orderBefore = this.categoryIds
    // Where each card was, not just what order the cards were in — see `#restore`.
    this.placeBefore = this.rowTargets.map((row) => [row, row.nextSibling])
    this.dropped = false
    event.dataTransfer.effectAllowed = "move"
    // Firefox will not begin a drag whose dataTransfer carries nothing.
    event.dataTransfer.setData("text/plain", this.dragged.dataset.categoryId)
    this.dragged.classList.add("opacity-50")
  }

  // Bound on the list, so the gaps between cards are drop targets and a drag released over one is
  // a drop rather than a cancel.
  over(event) {
    if (!this.dragged) return

    // preventDefault marks this a valid drop target; without it `drop` never fires.
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
    // A drag that ended where it started is not a reorder, and the write would still cost a page
    // load and a flash message.
    if (this.categoryIds.join() !== this.orderBefore.join()) this.submit()
  }

  // Each card back to its own recorded `nextSibling`, so non-targets are restored too. Walked in
  // reverse, because a sibling must be in place before the card that goes in front of it moves.
  restore() {
    for (let index = this.placeBefore.length - 1; index >= 0; index--) {
      const [row, next] = this.placeBefore[index]
      this.element.insertBefore(row, next)
    }
  }

  // The DOM order is the wire order: the list is drawn in PRIORITY order, the key
  // `Category.apply_fill_order` writes, so where the cards are IS the order.
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

  get categoryIds() {
    return this.rowTargets.map((row) => row.dataset.categoryId)
  }
}
