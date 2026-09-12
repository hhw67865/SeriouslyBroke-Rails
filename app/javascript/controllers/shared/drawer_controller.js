import { Controller } from "@hotwired/stimulus"

// Opens the dialog named by a trigger's data-drawer, closes one from inside it or off a backdrop
// click, and promotes a no-JS "open" render into a modal one on connect.
export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.dialogTargets.forEach(dialog => {
      if (!dialog.open) return

      dialog.close()
      dialog.showModal()
    })
  }

  open(event) {
    event.preventDefault()
    const name = event.currentTarget.dataset.drawer
    this.dialogTargets.find(dialog => dialog.dataset.drawerName === name)?.showModal()
  }

  close(event) {
    const { currentTarget: trigger, target } = event
    if (trigger.tagName === "DIALOG" && target !== trigger) return

    if (trigger.tagName === "A") event.preventDefault()
    trigger.closest("dialog")?.close()
  }
}
