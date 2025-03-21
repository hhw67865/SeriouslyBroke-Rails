import { Controller } from "@hotwired/stimulus"
import { Chart } from "chart.js/auto"

export default class extends Controller {
  static targets = ["container", "weekTab", "monthTab", "yearTab"]
  
  connect() {
    this.initializeChart()
    this.loadData('month') // Default to monthly view
  }

  initializeChart() {
    this.chart = new Chart(this.containerTarget, {
      type: 'line',
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: false
          }
        },
        scales: {
          y: {
            beginAtZero: true,
            ticks: {
              callback: value => `$${value}`
            }
          }
        }
      }
    })
  }

  async loadData(period) {
    try {
      const response = await fetch(`/api/spending_trend?period=${period}`)
      const data = await response.json()
      
      this.updateChart(data)
      this.updateTabs(period)
    } catch (error) {
      console.error('Error loading spending trend data:', error)
    }
  }

  updateChart(data) {
    this.chart.data = {
      labels: data.labels,
      datasets: [{
        data: data.values,
        borderColor: getComputedStyle(document.documentElement)
          .getPropertyValue('--color-primary')
          .trim(),
        tension: 0.4
      }]
    }
    this.chart.update()
  }

  updateTabs(period) {
    const activeClass = 'bg-white shadow-sm text-brand'
    const inactiveClass = ''
    
    this.weekTabTarget.className = `px-3 py-1 text-sm font-medium rounded-md ${
      period === 'week' ? activeClass : inactiveClass
    }`
    this.monthTabTarget.className = `px-3 py-1 text-sm font-medium rounded-md ${
      period === 'month' ? activeClass : inactiveClass
    }`
    this.yearTabTarget.className = `px-3 py-1 text-sm font-medium rounded-md ${
      period === 'year' ? activeClass : inactiveClass
    }`
  }

  week() {
    this.loadData('week')
  }

  month() {
    this.loadData('month')
  }

  year() {
    this.loadData('year')
  }
} 