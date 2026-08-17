import { Controller } from "@hotwired/stimulus"

// Dragging the Budget page's pool cards into a new fill order. Progressive enhancement only:
// the ▲▼ buttons beside each card already submit the same PATCH with the same `pool_ids[]`
// shape, so with scripting off the order is still reachable and nothing here is load-bearing.
//
// The cards are reordered in the DOM as the pointer moves and the new order is read back off
// them at drop, so there is one description of "the order" — where the cards actually are —
// rather than an index this controller keeps beside them and could get wrong.
export default class extends Controller {
  static targets = ["row", "form"]

  start(event) {
    this.dragged = event.currentTarget
    this.orderBefore = this.poolIds
    event.dataTransfer.effectAllowed = "move"
    // Firefox will not begin a drag whose dataTransfer carries nothing.
    event.dataTransfer.setData("text/plain", this.dragged.dataset.poolId)
    this.dragged.classList.add("opacity-50")
  }

  over(event) {
    const row = event.currentTarget
    if (!this.dragged || row === this.dragged) return

    // preventDefault is what marks this a valid drop target; without it the card springs back.
    event.preventDefault()
    const midpoint = row.getBoundingClientRect().top + row.offsetHeight / 2
    row.parentNode.insertBefore(this.dragged, event.clientY < midpoint ? row : row.nextSibling)
  }

  finish() {
    if (!this.dragged) return

    this.dragged.classList.remove("opacity-50")
    this.dragged = null
    // A drag that ended where it started is not a reorder, and a PATCH that rewrites the order
    // it already holds would still cost the user a page load and a flash message.
    if (this.poolIds.join() !== this.orderBefore.join()) this.submit()
  }

  submit() {
    const form = this.formTarget
    form.querySelectorAll("input[name='pool_ids[]']").forEach((input) => input.remove())
    this.poolIds.forEach((id) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "pool_ids[]"
      input.value = id
      form.appendChild(input)
    })
    form.requestSubmit()
  }

  get poolIds() {
    return this.rowTargets.map((row) => row.dataset.poolId)
  }
}
