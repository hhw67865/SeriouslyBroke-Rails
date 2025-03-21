import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message"]

  connect() {
    // Auto-dismiss after 5 seconds
    this.messageTargets.forEach(message => {
      setTimeout(() => {
        this.dismiss({ target: message })
      }, 5000)
    })
  }

  dismiss(event) {
    const message = event.target.closest('[data-flash-target="message"]')
    message.classList.add('opacity-0', 'transform', 'translate-y-2')
    message.style.transition = 'all 0.5s ease-out'
    
    setTimeout(() => {
      message.remove()
    }, 500)
  }
} 