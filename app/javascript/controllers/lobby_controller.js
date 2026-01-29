import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["gamesList"]

  connect() {
    console.log("Lobby controller connected")
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
          console.log("Connected to LobbyChannel")
          this.requestGamesList()
        },

        disconnected: () => {
          console.log("Disconnected from LobbyChannel")
        },

        received: (data) => {
          console.log("Received lobby data:", data)

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
        <div class="text-center py-8 text-gray-500">
          No active games. Create one to get started!
        </div>
      `
      return
    }

    this.gamesListTarget.innerHTML = games.map(game => this.renderGameCard(game)).join("")
  }

  renderGameCard(game) {
    const stateClass = game.state === "waiting" ? "bg-green-100" : "bg-blue-100"
    const stateText = game.state === "waiting" ? "Waiting" : "In Progress"
    const isFull = game.current_players >= game.max_players

    return `
      <div class="game-card ${stateClass} border rounded-lg p-4 mb-4">
        <div class="flex justify-between items-start">
          <div class="flex-1">
            <h3 class="text-xl font-bold mb-2">${this.escapeHtml(game.name)}</h3>

            <div class="grid grid-cols-2 gap-2 text-sm">
              <div>
                <span class="text-gray-600">Blinds:</span>
                <span class="font-semibold">${game.small_blind}/${game.big_blind}</span>
              </div>

              <div>
                <span class="text-gray-600">Buy-in:</span>
                <span class="font-semibold">${game.min_buyin} - ${game.max_buyin}</span>
              </div>

              <div>
                <span class="text-gray-600">Players:</span>
                <span class="font-semibold">${game.current_players}/${game.max_players}</span>
                ${isFull ? '<span class="text-red-600 ml-1">(Full)</span>' : ''}
              </div>

              <div>
                <span class="text-gray-600">Created by:</span>
                <span class="font-semibold">${this.escapeHtml(game.created_by)}</span>
              </div>
            </div>
          </div>

          <div class="ml-4 flex flex-col items-end">
            <span class="px-3 py-1 rounded-full text-sm font-semibold mb-2 ${
              game.state === "waiting" ? "bg-green-600 text-white" : "bg-blue-600 text-white"
            }">
              ${stateText}
            </span>

            ${!isFull ? `
              <a href="/games/${game.id}"
                 class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 transition">
                ${game.state === "waiting" ? "Join" : "Watch"}
              </a>
            ` : `
              <span class="px-4 py-2 bg-gray-400 text-white rounded cursor-not-allowed">
                Full
              </span>
            `}
          </div>
        </div>

        <div class="mt-2 text-xs text-gray-500">
          Created ${this.formatRelativeTime(game.created_at)}
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
