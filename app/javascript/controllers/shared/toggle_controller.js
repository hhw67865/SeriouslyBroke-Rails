import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="shared--toggle"
export default class extends Controller {
  static targets = ["content", "button", "icon"]

  toggle() {
    const isHidden = this.contentTarget.classList.toggle("hidden")

    if (this.hasButtonTarget) {
      this.buttonTarget.textContent = isHidden ? "View" : "Hide"
    }

    if (this.hasIconTarget) {
      this.iconTarget.classList.toggle("rotate-180", !isHidden)
    }
  }
}
