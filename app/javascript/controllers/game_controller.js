import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static values = {
    gameId: Number
  }

  static targets = [
    "pot",
    "round",
    "communityCards",
    "playersList",
    "holeCards",
    "actionButtons",
    "currentTurn",
    "statusMessage"
  ]

  connect() {
    console.log("Game controller connected for game:", this.gameIdValue)
    this.consumer = createConsumer()
    this.subscribeToGameChannel()
  }

  disconnect() {
    if (this.gameSubscription) {
      this.gameSubscription.unsubscribe()
    }
  }

  subscribeToGameChannel() {
    this.gameSubscription = this.consumer.subscriptions.create(
      { channel: "GameChannel", game_id: this.gameIdValue },
      {
        connected: () => {
          console.log("Connected to GameChannel")
          this.requestGameState()
        },

        disconnected: () => {
          console.log("Disconnected from GameChannel")
        },

        received: (data) => {
          console.log("Received data:", data)

          if (data.error) {
            this.showError(data.error)
            return
          }

          if (data.type === "game_state") {
            this.updateGameState(data)
          }
        }
      }
    )
  }

  requestGameState() {
    this.gameSubscription.perform("request_game_state")
  }

  updateGameState(data) {
    // Update pot
    if (this.hasPotTarget) {
      this.potTarget.textContent = data.game.pot
    }

    // Update round
    if (this.hasRoundTarget) {
      this.roundTarget.textContent = this.formatRound(data.game.round)
    }

    // Update community cards
    if (this.hasCommunityCardsTarget) {
      this.communityCardsTarget.innerHTML = this.renderCommunityCards(data.game.community_cards)
    }

    // Update players list
    if (this.hasPlayersListTarget) {
      this.playersListTarget.innerHTML = this.renderPlayers(data.players, data.game.current_player_position)
    }

    if (this.hasHoleCardsTarget && data.your_hole_cards) {
      this.holeCardsTarget.innerHTML = this.renderHoleCards(data.your_hole_cards)
    }

    if (this.hasActionButtonsTarget) {
      this.updateActionButtons(data.is_your_turn, data.game.state)
    }

    if (this.hasCurrentTurnTarget) {
      if (data.is_your_turn) {
        this.currentTurnTarget.textContent = "Your Turn!"
        this.currentTurnTarget.classList.add("text-green-600", "font-bold")
      } else {
        const currentPlayer = data.players.find(p => p.is_current_player)
        this.currentTurnTarget.textContent = currentPlayer ? `Waiting for ${currentPlayer.username}...` : "Waiting..."
        this.currentTurnTarget.classList.remove("text-green-600", "font-bold")
      }
    }
  }

  performAction(event) {
    const actionType = event.target.dataset.action.split("#")[1]
    const amount = this.getActionAmount(actionType)

    this.gameSubscription.perform("perform_action", {
      action_type: actionType,
      amount: amount
    })

    if (this.hasActionButtonsTarget) {
      const buttons = this.actionButtonsTarget.querySelectorAll("button")
      buttons.forEach(btn => btn.disabled = true)
    }
  }

  getActionAmount(actionType) {
    if (actionType === "raise" || actionType === "bet") {
      const amountInput = document.querySelector("[data-game-target='raiseAmount']")
      return amountInput ? parseInt(amountInput.value) : null
    }
    return null
  }

  updateActionButtons(isYourTurn, gameState) {
    if (gameState !== "in_progress") {
      this.actionButtonsTarget.classList.add("hidden")
      return
    }

    const buttons = this.actionButtonsTarget.querySelectorAll("button")
    buttons.forEach(btn => {
      btn.disabled = !isYourTurn
    })

    if (isYourTurn) {
      this.actionButtonsTarget.classList.remove("hidden")
    }
  }

  renderCommunityCards(cards) {
    if (!cards || cards.length === 0) {
      return '<div class="text-gray-500">No community cards yet</div>'
    }

    return cards.map(card => `
      <div class="card">
        <span class="text-2xl font-bold">${this.formatCard(card)}</span>
      </div>
    `).join("")
  }

  renderHoleCards(cards) {
    if (!cards || cards.length === 0) {
      return '<div class="text-gray-500">No hole cards</div>'
    }

    return cards.map(card => `
      <div class="card">
        <span class="text-xl font-bold">${this.formatCard(card)}</span>
      </div>
    `).join("")
  }

  renderPlayers(players, currentPlayerPosition) {
    return players.map(player => `
      <div class="player ${player.position === currentPlayerPosition ? 'current-player' : ''}" data-position="${player.position}">
        <div class="player-name">${player.username}</div>
        <div class="player-chips">Chips: ${player.chips}</div>
        <div class="player-status">${this.formatStatus(player.status)}</div>
        ${player.is_current_player ? '<div class="turn-indicator">●</div>' : ''}
      </div>
    `).join("")
  }

  formatCard(card) {
    const rank = card[0]
    const suit = card[1]
    const suitSymbols = { h: "♥️", d: "♦️", c: "♣️", s: "♠️" }
    const rankNames = { T: "10", J: "J", Q: "Q", K: "K", A: "A" }

    return `${rankNames[rank] || rank}${suitSymbols[suit]}`
  }

  formatRound(round) {
    const rounds = {
      preflop: "Pre-Flop",
      flop: "Flop",
      turn: "Turn",
      river: "River",
      showdown: "Showdown"
    }
    return rounds[round] || round
  }

  formatStatus(status) {
    const statuses = {
      active: "Active",
      folded: "Folded",
      all_in: "All-in",
      sitting_out: "Sitting Out",
      left: "Left"
    }
    return statuses[status] || status
  }

  showError(message) {
    if (this.hasStatusMessageTarget) {
      this.statusMessageTarget.textContent = message
      this.statusMessageTarget.classList.remove("hidden")
      this.statusMessageTarget.classList.add("text-red-600")

      setTimeout(() => {
        this.statusMessageTarget.classList.add("hidden")
      }, 3000)
    } else {
      alert(message)
    }
  }
}
