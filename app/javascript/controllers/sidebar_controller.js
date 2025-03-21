import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "overlay"]

  connect() {
    // Handle escape key
    this.handleEscapeKey = this.handleEscapeKey.bind(this)
    document.addEventListener('keydown', this.handleEscapeKey)
    
    // Handle initial state
    this.updateVisibility()
    
    // Handle resize
    this.resizeObserver = new ResizeObserver(this.updateVisibility.bind(this))
    this.resizeObserver.observe(document.body)
  }

  disconnect() {
    document.removeEventListener('keydown', this.handleEscapeKey)
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
  }

  toggle() {
    if (this.panelTarget.classList.contains('-translate-x-full')) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.panelTarget.classList.remove('-translate-x-full')
    this.overlayTarget.classList.remove('hidden')
    document.body.classList.add('overflow-hidden')
  }

  close() {
    if (window.innerWidth < 1024) { // Only close on mobile
      this.panelTarget.classList.add('-translate-x-full')
      this.overlayTarget.classList.add('hidden')
      document.body.classList.remove('overflow-hidden')
    }
  }

  handleEscapeKey(event) {
    if (event.key === 'Escape') {
      this.close()
    }
  }

  updateVisibility() {
    if (window.innerWidth >= 1024) { // lg breakpoint
      this.panelTarget.classList.remove('-translate-x-full')
      this.overlayTarget.classList.add('hidden')
      document.body.classList.remove('overflow-hidden')
    } else {
      this.panelTarget.classList.add('-translate-x-full')
      this.overlayTarget.classList.add('hidden')
    }
  }
} 