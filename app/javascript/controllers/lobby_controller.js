import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["gamesList"]

  connect() {
    this.consumer = createConsumer()
    this.subscribeToLobbyChannel()
  }

  disconnect() {
    if (this.lobbySubscription) {
      this.lobbySubscription.unsubscribe()
    }
  }

  subscribeToLobbyChannel() {
    this.lobbySubscription = this.consumer.subscriptions.create(
      { channel: "LobbyChannel" },
      {
        connected: () => {
          this.requestGamesList()
        },

        disconnected: () => {},

        received: (data) => {
          if (data.type === "games_list") {
            this.updateGamesList(data.games)
          }
        }
      }
    )
  }

  requestGamesList() {
    this.lobbySubscription.perform("request_games_list")
  }

  updateGamesList(games) {
    if (!this.hasGamesListTarget) return

    if (games.length === 0) {
      this.gamesListTarget.innerHTML = `
        <div class="p-12 text-center">
          <div class="w-16 h-16 bg-white/5 rounded-2xl flex items-center justify-center mx-auto mb-4">
            <svg class="w-8 h-8 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
            </svg>
          </div>
          <h3 class="text-lg font-semibold text-white mb-2">No Tables Available</h3>
          <p class="text-gray-400 mb-6">Be the first to create a table and start playing!</p>
          <button onclick="document.getElementById('createGameModal').classList.remove('hidden')"
                  class="inline-flex items-center px-6 py-3 bg-gradient-to-r from-emerald-500 to-emerald-600 hover:from-emerald-400 hover:to-emerald-500 text-white font-semibold rounded-xl transition-all">
            Create Your Table
          </button>
        </div>
      `
      return
    }

    this.gamesListTarget.innerHTML = `<div class="divide-y divide-white/10">${games.map(game => this.renderGameCard(game)).join("")}</div>`
  }

  renderGameCard(game) {
    const stateText = game.state === "waiting" ? "Waiting" : "In Progress"
    const isFull = game.current_players >= game.max_players

    return `
      <div class="p-6 hover:bg-white/5 transition-colors">
        <div class="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
          <div class="flex-1">
            <div class="flex items-center space-x-3 mb-2">
              <h3 class="text-lg font-semibold text-white">${this.escapeHtml(game.name)}</h3>
              <span class="px-3 py-1 rounded-full text-xs font-semibold ${game.state === 'waiting' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-blue-500/20 text-blue-400'}">
                ${stateText}
              </span>
            </div>

            <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
              <div>
                <span class="text-gray-500">Blinds</span>
                <p class="text-white font-medium">${game.small_blind}/${game.big_blind}</p>
              </div>
              <div>
                <span class="text-gray-500">Buy-in</span>
                <p class="text-white font-medium">${game.min_buyin} - ${game.max_buyin}</p>
              </div>
              <div>
                <span class="text-gray-500">Players</span>
                <p class="text-white font-medium">${game.current_players}/${game.max_players}</p>
              </div>
              <div>
                <span class="text-gray-500">Created by</span>
                <p class="text-white font-medium">${this.escapeHtml(game.created_by)}</p>
              </div>
            </div>
          </div>

          <div class="flex items-center space-x-3">
            ${isFull ? `
              <span class="px-6 py-3 bg-white/5 text-gray-400 rounded-xl">Table Full</span>
            ` : game.state === 'waiting' ? `
              <button onclick="openJoinModal(${game.id}, '${this.escapeHtml(game.name)}', ${game.min_buyin}, ${game.max_buyin})"
                      class="px-6 py-3 bg-gradient-to-r from-blue-500 to-blue-600 hover:from-blue-400 hover:to-blue-500 text-white font-semibold rounded-xl shadow-lg shadow-blue-500/25 hover:shadow-blue-500/40 transition-all">
                Join Table
              </button>
            ` : `
              <a href="/games/${game.id}" class="px-6 py-3 bg-white/10 hover:bg-white/20 text-white font-semibold rounded-xl transition-all">
                Watch
              </a>
            `}
          </div>
        </div>
      </div>
    `
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  formatRelativeTime(timestamp) {
    const date = new Date(timestamp)
    const now = new Date()
    const seconds = Math.floor((now - date) / 1000)

    if (seconds < 60) return "just now"
    if (seconds < 3600) return `${Math.floor(seconds / 60)} minutes ago`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)} hours ago`
    return `${Math.floor(seconds / 86400)} days ago`
  }

  refresh(event) {
    event.preventDefault()
    this.requestGamesList()
  }
}
