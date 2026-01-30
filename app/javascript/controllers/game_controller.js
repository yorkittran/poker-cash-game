import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static values = {
    gameId: Number,
    yourPosition: Number
  }

  static targets = [
    "pot",
    "round",
    "communityCards",
    "playersList",
    "holeCards",
    "actionButtons",
    "currentTurn",
    "statusMessage",
    "actionLog",
    "handNumber",
    "readyPlayersList",
    "readyCount",
    "readyButton",
    "checkButtonWrapper",
    "callButtonWrapper",
    "countdown",
    "showdownIndicator"
  ]

  connect() {
    this.consumer = createConsumer()
    this.previousGameState = null
    this.gameStateReceived = false
    this.retryCount = 0
    this.maxRetries = 3
    this.countdownInterval = null
    this.winnerAlertTimeout = null
    this.showdownMode = false
    this.showdownTimer = null

    if (this.hasYourPositionValue) {
      const posValue = this.yourPositionValue
      this.yourPosition = (posValue !== null && posValue !== undefined && !isNaN(posValue)) ? parseInt(posValue) : null
    } else {
      this.yourPosition = null
    }

    this.myHoleCards = this.readHoleCardsFromDOM()
    this.subscribeToGameChannel()
  }

  readHoleCardsFromDOM() {
    let container = this.hasHoleCardsTarget ? this.holeCardsTarget : null

    if (!container && this.hasPlayersListTarget) {
      container = this.playersListTarget.querySelector('[data-game-target="holeCards"]')
    }

    if (!container) {
      container = this.element.querySelector('[data-game-target="holeCards"]')
    }

    if (!container) return null

    const cardElements = container.querySelectorAll('div.bg-white')
    if (cardElements.length === 0) return null

    const cards = []
    cardElements.forEach(cardEl => {
      const spans = cardEl.querySelectorAll('span')
      if (spans.length >= 2) {
        const rank = spans[0].textContent.trim()
        const suit = spans[1].textContent.trim()
        const suitToLetter = { '♥': 'h', '♦': 'd', '♣': 'c', '♠': 's' }
        const suitLetter = suitToLetter[suit] || suit
        const rankChar = rank === '10' ? 'T' : rank
        cards.push(rankChar + suitLetter)
      }
    })

    return cards.length > 0 ? cards : null
  }

  disconnect() {
    this.stopShowdownAutoAdvance()
    if (this.gameSubscription) {
      this.gameSubscription.unsubscribe()
    }
    if (this.countdownInterval) {
      clearInterval(this.countdownInterval)
    }
    if (this.winnerAlertTimeout) {
      clearTimeout(this.winnerAlertTimeout)
    }
  }

  subscribeToGameChannel() {
    this.gameSubscription = this.consumer.subscriptions.create(
      { channel: "GameChannel", game_id: this.gameIdValue },
      {
        connected: () => {
          setTimeout(() => this.requestGameState(), 100)
        },

        disconnected: () => {},

        rejected: () => {
          console.error("Connection rejected by server")
        },

        received: (data) => {
          if (data.error) {
            this.showError(data.error)
            this.enableActionButtons()
            if (!this.gameStateReceived && this.retryCount < this.maxRetries) {
              this.retryCount++
              setTimeout(() => this.requestGameState(), 1000)
            }
            return
          }

          if (data.success && data.redirect) {
            window.location.href = data.redirect
            return
          }

          if (data.success && data.message) {
            this.showSuccess(data.message)
          }

          if (data.type === "game_state" && data.game) {
            this.gameStateReceived = true
            this.retryCount = 0
            this.updateGameState(data)
          } else if (data.type === "game_state") {
            setTimeout(() => this.requestGameState(), 500)
          }
        }
      }
    )
  }

  requestGameState() {
    if (!this.gameSubscription) return
    this.gameSubscription.perform("request_game_state")
  }

  updateGameState(data) {
    if (data.game.state === 'in_progress' && this.hasReadyPlayersListTarget) {
      window.location.reload()
      return
    }

    if (this.previousGameState === 'waiting' && data.game.state === 'in_progress') {
      window.location.reload()
      return
    }
    this.previousGameState = data.game.state

    if (data.your_position !== undefined && data.your_position !== null) {
      this.yourPosition = parseInt(data.your_position)
    }

    const currentPos = parseInt(data.game.current_player_position)
    const myPos = this.yourPosition

    let isYourTurn = false
    if (data.is_your_turn !== undefined) {
      isYourTurn = data.is_your_turn
    } else if (myPos !== null && myPos !== undefined && !isNaN(myPos)) {
      isYourTurn = myPos === currentPos
    }

    // Update waiting room (ready status) if game is waiting
    if (data.game.state === 'waiting') {
      this.updateReadyStatus(data.players)
    }

    // Handle showdown mode
    if (data.game.showdown_mode && !this.showdownMode) {
      // Just entered showdown mode
      this.showdownMode = true
      this.startShowdownAutoAdvance()
      if (this.hasShowdownIndicatorTarget) {
        this.showdownIndicatorTarget.classList.remove('hidden')
      }
    } else if (!data.game.showdown_mode && this.showdownMode) {
      // Exited showdown mode (hand completed)
      this.showdownMode = false
      this.stopShowdownAutoAdvance()
      if (this.hasShowdownIndicatorTarget) {
        this.showdownIndicatorTarget.classList.add('hidden')
      }

      // When exiting showdown mode, if there are winners, show countdown
      if (data.winners && data.winners.length > 0) {
        if (this.countdownInterval) {
          clearInterval(this.countdownInterval)
          this.countdownInterval = null
        }
        this.showWinnerAlert(data.winners)
        this.startCountdown(5)
      }
    }

    // Update pot
    if (this.hasPotTarget) {
      this.potTarget.textContent = data.game.pot.toLocaleString()
    }

    // Update round
    if (this.hasRoundTarget) {
      this.roundTarget.textContent = this.formatRound(data.game.round)
    }

    // Update hand number
    if (this.hasHandNumberTarget) {
      this.handNumberTarget.textContent = data.game.current_hand_number
    }

    if (data.winners && data.winners.length > 0 && !data.game.showdown_mode) {
      // Only show winner alert and countdown when winners are present AND showdown mode is over
      // Clear any existing countdown first
      if (this.countdownInterval) {
        clearInterval(this.countdownInterval)
        this.countdownInterval = null
      }

      this.showWinnerAlert(data.winners)
      this.startCountdown(5)
    }

    // Update community cards
    if (this.hasCommunityCardsTarget) {
      this.communityCardsTarget.innerHTML = this.renderCommunityCards(data.game.community_cards)
    }

    const isNewHand = this.currentHandNumber && data.game.current_hand_number !== this.currentHandNumber
    if (isNewHand) {
      this.myHoleCards = null

      if (this.countdownInterval) {
        clearInterval(this.countdownInterval)
        this.countdownInterval = null
      }
      if (this.hasCountdownTarget) {
        this.countdownTarget.classList.add('hidden')
      }

      if (this.winnerAlertTimeout) {
        clearTimeout(this.winnerAlertTimeout)
        this.winnerAlertTimeout = null
      }
      const existingAlert = document.getElementById('winner-alert')
      if (existingAlert) {
        existingAlert.remove()
      }

      this.currentHandNumber = data.game.current_hand_number
      this.requestGameState()
      return
    }
    this.currentHandNumber = data.game.current_hand_number

    if (data.your_hole_cards && data.your_hole_cards.length > 0) {
      this.myHoleCards = data.your_hole_cards
    }

    if (!this.myHoleCards && data.players) {
      const myPlayerData = data.players.find(p => p.position === this.yourPosition)
      if (myPlayerData && myPlayerData.hole_cards && myPlayerData.hole_cards.length > 0) {
        this.myHoleCards = myPlayerData.hole_cards
      }
    }

    if (!this.myHoleCards && data.game.state === 'in_progress' && this.yourPosition !== null) {
      const domCards = this.readHoleCardsFromDOM()
      if (domCards) {
        this.myHoleCards = domCards
      }
    }

    if (!this.myHoleCards && this.hasPlayersListTarget) {
      const domCards = this.readHoleCardsFromDOM()
      if (domCards) {
        this.myHoleCards = domCards
      }
    }

    // Update individual player seats with new data
    if (data.players) {
      this.updatePlayerSeats(data.players, data.game.current_player_position, data.game.dealer_position, this.myHoleCards, data.game.round, data.winners)
    }

    // Update separate hole cards display if exists
    if (this.hasHoleCardsTarget && this.myHoleCards) {
      this.holeCardsTarget.innerHTML = this.renderHoleCards(this.myHoleCards)
    }

    // Find current player's data
    const myPlayer = data.players.find(p => p.position === this.yourPosition)

    // Check if player needs to rebuy (sitting_out with 0 chips)
    if (myPlayer && myPlayer.status === 'sitting_out' && myPlayer.chips === 0) {
      this.showRebuyPrompt(data.game)
    } else if (this.hasActionButtonsTarget) {
      this.updateActionButtons(isYourTurn, data.game, myPlayer, data.players, data.winners)
    }

    if (this.hasCurrentTurnTarget) {
      // Show different message if hand is complete (has winners)
      if (data.winners && data.winners.length > 0) {
        this.currentTurnTarget.innerHTML = '<span class="text-amber-400 font-semibold text-lg">Hand Complete</span>'
      } else if (myPlayer && myPlayer.status === 'sitting_out' && myPlayer.chips === 0) {
        this.currentTurnTarget.innerHTML = '<span class="text-red-400 font-semibold text-lg">Out of Chips - Rebuy to Continue</span>'
      } else if (isYourTurn) {
        this.currentTurnTarget.innerHTML = '<span class="text-emerald-400 font-semibold text-lg">Your Turn!</span>'
      } else {
        const currentPlayer = data.players.find(p => p.is_current_player)
        this.currentTurnTarget.innerHTML = `<span class="text-gray-400">Waiting for ${currentPlayer?.username || 'next player'}...</span>`
      }
    }

    // Update action log
    if (this.hasActionLogTarget && data.actions) {
      this.actionLogTarget.innerHTML = this.renderActionLog(data.actions)
    }
  }

  renderActionLog(actions) {
    if (!actions || actions.length === 0) {
      return '<p class="text-white/60 text-center py-4">No actions yet</p>'
    }

    const actionsByRound = {}
    actions.forEach(action => {
      if (!actionsByRound[action.round]) {
        actionsByRound[action.round] = []
      }
      actionsByRound[action.round].push(action)
    })

    if (Object.keys(actionsByRound).length === 0) {
      return '<p class="text-white/60 text-center py-4">No actions yet</p>'
    }

    return Object.entries(actionsByRound).map(([round, roundActions]) => {
      const actionsHtml = roundActions.map(action => {
        const colorClass = action.action_type === 'fold' ? 'text-red-400' :
                           action.action_type === 'call' ? 'text-emerald-400' :
                           action.action_type === 'raise' || action.action_type === 'bet' ? 'text-amber-400' :
                           action.action_type === 'all_in' ? 'text-red-500' : 'text-blue-400'

        return `
          <div class="flex items-center justify-between text-xs py-1">
            <span class="text-white truncate flex-1">${action.username}</span>
            <span class="${colorClass} uppercase font-bold w-12 text-center">${action.action_type}</span>
            <span class="text-white font-medium w-10 text-right">${action.amount && action.amount > 0 ? `$${action.amount}` : ''}</span>
          </div>
        `
      }).join("")

      return `
        <div class="space-y-2">
          <div class="text-[10px] text-white/50 uppercase font-bold tracking-wide border-b border-white/10 pb-1.5 mb-2">${round}</div>
          ${actionsHtml}
        </div>
      `
    }).join("")
  }

  updateReadyStatus(players) {
    // Update the ready players list
    if (this.hasReadyPlayersListTarget) {
      this.readyPlayersListTarget.innerHTML = players.map(player => `
        <div class="flex items-center justify-between p-3 rounded-xl ${player.ready ? 'bg-emerald-500/20 border border-emerald-500/30' : 'bg-white/5 border border-white/10'}">
          <div class="flex items-center gap-2">
            <div class="w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-sm ${player.ready ? 'bg-emerald-500' : 'bg-slate-600'}">
              ${player.username.substring(0, 2).toUpperCase()}
            </div>
            <span class="text-white font-medium text-sm">${player.username}</span>
          </div>
          <span class="${player.ready ? 'text-emerald-400' : 'text-gray-500'} text-sm font-semibold">
            ${player.ready ? '✓ Ready' : 'Not Ready'}
          </span>
        </div>
      `).join("")
    }

    // Update the ready count
    if (this.hasReadyCountTarget) {
      const readyCount = players.filter(p => p.ready).length
      const totalCount = players.length
      let countHtml = `${readyCount}/${totalCount} players ready`
      if (totalCount < 2) {
        countHtml += ' <span class="text-amber-400">(need at least 2 players)</span>'
      }
      this.readyCountTarget.innerHTML = countHtml
    }
  }

  performAction(event) {
    event.preventDefault()
    const button = event.currentTarget
    const actionType = button.dataset.actionType
    const amount = this.getActionAmount(actionType)

    this.gameSubscription.perform("player_action", {
      action_type: actionType,
      amount: amount
    })

    this.disableActionButtons()
  }

  disableActionButtons() {
    if (this.hasActionButtonsTarget) {
      const buttons = this.actionButtonsTarget.querySelectorAll("button")
      buttons.forEach(btn => btn.disabled = true)
    }
  }

  enableActionButtons() {
    if (this.hasActionButtonsTarget) {
      const buttons = this.actionButtonsTarget.querySelectorAll("button")
      buttons.forEach(btn => btn.disabled = false)
    }
  }

  toggleReady(event) {
    event.preventDefault()
    this.gameSubscription.perform("toggle_ready", {})
  }

  leaveGame(event) {
    event.preventDefault()
    if (!confirm("Are you sure you want to leave? You'll cash out.")) {
      return
    }
    this.gameSubscription.perform("leave_game", {})
  }

  performRebuy(event) {
    event.preventDefault()
    const form = event.target
    const amount = parseInt(form.querySelector('[name="rebuy_amount"]').value)

    this.gameSubscription.perform("rebuy", {
      rebuy_amount: amount
    })
  }

  getActionAmount(actionType) {
    if (actionType === "raise" || actionType === "bet") {
      const amountInput = document.querySelector("[data-game-target='raiseAmount']")
      return amountInput ? parseInt(amountInput.value) : null
    }
    return null
  }

  updateActionButtons(isYourTurn, game, myPlayer, allPlayers, winners = null) {
    if (game.state !== "in_progress") {
      this.actionButtonsTarget.classList.add("hidden")
      return
    }

    if (winners && winners.length > 0) {
      this.actionButtonsTarget.classList.add("hidden")
      return
    }

    if (this.showdownMode) {
      this.actionButtonsTarget.classList.add("hidden")
      return
    }

    this.actionButtonsTarget.classList.remove("hidden")

    const allBets = allPlayers.map(p => p.current_bet || 0)
    const currentMaxBet = Math.max(...allBets, 0)

    const uniqueBets = [...new Set(allBets)].sort((a, b) => b - a)
    let minRaise
    if (uniqueBets.length >= 2) {
      const lastRaiseSize = uniqueBets[0] - uniqueBets[1]
      minRaise = currentMaxBet + lastRaiseSize
    } else {
      minRaise = currentMaxBet > 0 ? currentMaxBet * 2 : game.big_blind * 2
    }

    const myBet = myPlayer?.current_bet || 0
    const amountToCall = currentMaxBet - myBet
    const myChips = myPlayer?.chips || 0

    const canCheck = amountToCall <= 0
    const canCall = amountToCall > 0
    const callAmount = Math.min(amountToCall, myChips)

    if (this.hasCheckButtonWrapperTarget) {
      if (canCheck) {
        this.checkButtonWrapperTarget.classList.remove('hidden')
      } else {
        this.checkButtonWrapperTarget.classList.add('hidden')
      }
    }
    if (this.hasCallButtonWrapperTarget) {
      if (canCall) {
        this.callButtonWrapperTarget.classList.remove('hidden')
        const callBtn = this.callButtonWrapperTarget.querySelector('button')
        if (callBtn) {
          callBtn.textContent = `Call ${callAmount}`
        }
      } else {
        this.callButtonWrapperTarget.classList.add('hidden')
      }
    }

    this.actionButtonsTarget.querySelectorAll("button[data-action-type]").forEach(btn => {
      const actionType = btn.dataset.actionType

      if (!actionType) return

      let shouldEnable = isYourTurn

      if (actionType === 'check') {
        shouldEnable = isYourTurn && canCheck
        btn.textContent = 'Check'
      } else if (actionType === 'call') {
        shouldEnable = isYourTurn && canCall
        btn.textContent = canCall ? `Call ${callAmount}` : 'Call'
      } else if (actionType === 'raise') {
        btn.textContent = canCall ? 'Raise to' : 'Bet'
      } else if (actionType === 'all_in') {
        btn.textContent = `All In (${myChips})`
      }

      btn.disabled = !shouldEnable
    })

    const raiseAmountInput = this.actionButtonsTarget.querySelector('[data-game-target="raiseAmount"]')
    if (raiseAmountInput) {
      raiseAmountInput.min = minRaise
      raiseAmountInput.max = myChips + myBet
      raiseAmountInput.value = Math.max(parseInt(raiseAmountInput.value) || minRaise, minRaise)
      raiseAmountInput.disabled = !isYourTurn
    }

    this.actionButtonsTarget.classList.remove("hidden")
    if (this.hasCurrentTurnTarget) {
      if (isYourTurn) {
        let turnText = 'Your Turn!'
        if (canCall) {
          turnText += ` (${callAmount} to call)`
        }
        this.currentTurnTarget.innerHTML = `<span class="text-emerald-400 font-semibold text-lg">${turnText}</span>`
      }
    }
  }

  renderCommunityCards(cards) {
    let html = ''
    for (let i = 0; i < 5; i++) {
      if (cards && cards[i]) {
        const { rank, suit, colorClass } = this.formatCard(cards[i])
        html += `
          <div class="bg-white rounded-lg shadow-lg flex flex-col items-center justify-center font-bold ${colorClass} border border-gray-200" style="width: 52px; height: 72px;">
            <span class="text-base leading-none">${rank}</span>
            <span class="text-xl leading-none">${suit}</span>
          </div>
        `
      } else {
        html += '<div class="bg-emerald-700/30 rounded-lg border-2 border-emerald-600/20" style="width: 52px; height: 72px;"></div>'
      }
    }
    return html
  }

  renderHoleCards(cards) {
    if (!cards || cards.length === 0) {
      return ''
    }

    return cards.map(card => {
      const { rank, suit, colorClass } = this.formatCard(card)
      return `
        <div class="bg-white rounded-lg shadow-lg flex flex-col items-center justify-center font-bold ${colorClass} border border-gray-200" style="width: 32px; height: 44px;">
          <span class="text-xs leading-none">${rank}</span>
          <span class="text-sm leading-none">${suit}</span>
        </div>
      `
    }).join("")
  }

  updatePlayerSeats(players, currentPlayerPosition, dealerPosition, yourHoleCards, round = null, winners = null) {
    for (let position = 0; position < 8; position++) {
      const seat = document.querySelector(`[data-position="${position}"]`)
      if (!seat) continue

      const player = players.find(p => p.position === position)

      if (player) {
        const isCurrentPlayer = player.position === currentPlayerPosition
        const isFolded = player.status === 'folded'
        const isAllIn = player.status === 'all_in'
        const isSittingOut = player.status === 'sitting_out'
        const isDealer = player.position === dealerPosition
        const isYou = player.position === this.yourPosition
        const isWinner = winners && winners.some(w => w.user_id === player.user_id)
        const avatarClass = isCurrentPlayer
          ? 'bg-gradient-to-br from-amber-400 to-amber-600 ring-4 ring-amber-400/50 animate-pulse'
          : isSittingOut
          ? 'bg-gradient-to-br from-gray-500 to-gray-600'
          : 'bg-gradient-to-br from-slate-600 to-slate-700'

        const opacityClass = (isFolded || isSittingOut) ? 'opacity-50' : ''

        let holeCardsHtml = ''
        const playerHoleCards = isYou && yourHoleCards ? yourHoleCards : player.hole_cards

        if (playerHoleCards && playerHoleCards.length > 0) {
          holeCardsHtml = `<div class="flex gap-2 mt-2">${this.renderHoleCards(playerHoleCards)}</div>`
        } else if (player.status === 'active' || player.status === 'all_in') {
          holeCardsHtml = `
            <div class="flex gap-2 mt-2">
              <div class="rounded border-2 border-white shadow-lg" style="width: 32px; height: 44px; background: linear-gradient(135deg, #10b981 0%, #065f46 100%);">
                <div class="w-full h-full flex items-center justify-center">
                  <div class="w-5 h-7 border-2 border-white/60 rounded"></div>
                </div>
              </div>
              <div class="rounded border-2 border-white shadow-lg" style="width: 32px; height: 44px; background: linear-gradient(135deg, #10b981 0%, #065f46 100%);">
                <div class="w-full h-full flex items-center justify-center">
                  <div class="w-5 h-7 border-2 border-white/60 rounded"></div>
                </div>
              </div>
            </div>
          `
        } else if (player.status === 'folded') {
          holeCardsHtml = `
            <div class="flex gap-2 mt-2">
              <div class="rounded border-2 border-white/30 shadow-lg" style="width: 32px; height: 44px; background: linear-gradient(135deg, #10b981 0%, #065f46 100%);">
                <div class="w-full h-full flex items-center justify-center">
                  <div class="w-5 h-7 border-2 border-white/40 rounded"></div>
                </div>
              </div>
              <div class="rounded border-2 border-white/30 shadow-lg" style="width: 32px; height: 44px; background: linear-gradient(135deg, #10b981 0%, #065f46 100%);">
                <div class="w-full h-full flex items-center justify-center">
                  <div class="w-5 h-7 border-2 border-white/40 rounded"></div>
                </div>
              </div>
            </div>
          `
        } else if (player.status === 'sitting_out') {
          holeCardsHtml = `
            <div class="flex gap-2 mt-2">
              <div class="bg-gray-600/30 rounded border border-gray-500/30" style="width: 32px; height: 44px;"></div>
              <div class="bg-gray-600/30 rounded border border-gray-500/30" style="width: 32px; height: 44px;"></div>
            </div>
          `
        } else {
          holeCardsHtml = `
            <div class="flex gap-2 mt-2">
              <div class="bg-slate-700/30 rounded" style="width: 32px; height: 44px;"></div>
              <div class="bg-slate-700/30 rounded" style="width: 32px; height: 44px;"></div>
            </div>
          `
        }

        let betHtml = ''
        if (player.current_bet > 0 && !isFolded) {
          betHtml = `
            <div class="mt-2 flex flex-col items-center">
              <div class="w-12 h-12 rounded-full flex items-center justify-center shadow-lg" style="background-color: #f59e0b;">
                <span class="text-white text-xs font-bold">${player.current_bet.toLocaleString()}</span>
              </div>
              ${isWinner ? '<div class="mt-1 px-2 py-0.5 bg-amber-500 rounded-full text-[10px] font-bold text-white whitespace-nowrap">WINNER</div>' : ''}
            </div>
          `
        } else if (isWinner) {
          betHtml = `
            <div class="mt-2 px-2 py-0.5 bg-amber-500 rounded-full text-[10px] font-bold text-white whitespace-nowrap">WINNER</div>
          `
        }

        seat.innerHTML = `
          <div class="flex flex-col items-center">
            <div class="relative">
              <div class="w-16 h-16 rounded-full flex items-center justify-center text-white font-bold shadow-lg ${avatarClass} ${opacityClass}">
                ${player.username.substring(0, 2).toUpperCase()}
              </div>
              ${isDealer ? '<div class="absolute -top-1 -right-1 w-6 h-6 bg-white rounded-full flex items-center justify-center text-xs font-bold text-black shadow-lg">D</div>' : ''}
              ${isAllIn ? '<div class="absolute -bottom-1 left-1/2 -translate-x-1/2 px-2 py-1 bg-red-500 rounded-full text-[10px] font-bold text-white whitespace-nowrap">ALL IN</div>' : ''}
              ${isSittingOut ? '<div class="absolute -bottom-1 left-1/2 -translate-x-1/2 px-2 py-1 bg-gray-500 rounded-full text-[10px] font-bold text-white whitespace-nowrap">SITTING OUT</div>' : ''}
            </div>
            <div class="mt-2 text-center">
              <p class="text-white text-sm font-medium">${player.username}</p>
              <p class="text-emerald-400 text-xs font-semibold">$${player.chips.toLocaleString()}</p>
            </div>
            ${holeCardsHtml}
            ${betHtml}
          </div>
        `
      } else {
        seat.innerHTML = `
          <div class="flex flex-col items-center opacity-50">
            <div class="w-16 h-16 rounded-full bg-white/10 border-2 border-white/20 border-dashed flex items-center justify-center">
              <span class="text-white text-xs font-medium">P${position + 1}</span>
            </div>
            <div class="mt-2 text-center">
              <p class="text-white text-xs">Empty</p>
            </div>
            <div class="flex gap-2 mt-2">
              <div class="bg-white/10 border border-white/20 border-dashed rounded" style="width: 32px; height: 44px;"></div>
              <div class="bg-white/10 border border-white/20 border-dashed rounded" style="width: 32px; height: 44px;"></div>
            </div>
          </div>
        `
      }
    }
  }

  renderPlayers(players, currentPlayerPosition, yourPosition = null, yourHoleCards = null) {
    const positions = [
      { top: '2%', left: '50%', transform: 'translateX(-50%)' },
      { top: '15%', left: '80%', transform: 'translateX(-50%)' },
      { top: '50%', left: '95%', transform: 'translate(-50%, -50%)' },
      { top: '85%', left: '80%', transform: 'translateX(-50%)' },
      { top: '98%', left: '50%', transform: 'translate(-50%, -100%)' },
      { top: '85%', left: '20%', transform: 'translateX(-50%)' },
      { top: '50%', left: '5%', transform: 'translate(-50%, -50%)' },
      { top: '15%', left: '20%', transform: 'translateX(-50%)' },
      { top: '8%', left: '35%', transform: 'translateX(-50%)' }
    ]

    return players.map(player => {
      const pos = positions[player.position] || positions[0]
      const isCurrentPlayer = player.position === currentPlayerPosition
      const isFolded = player.status === 'folded'
      const isAllIn = player.status === 'all_in'
      const isYou = player.position === yourPosition

      const avatarClass = isCurrentPlayer
        ? 'bg-gradient-to-br from-amber-400 to-amber-600 ring-2 ring-amber-400/50 animate-pulse'
        : 'bg-gradient-to-br from-slate-600 to-slate-700'

      const playerHoleCards = isYou && yourHoleCards ? yourHoleCards : player.hole_cards
      let holeCardsHtml = ''

      if (playerHoleCards && playerHoleCards.length > 0) {
        holeCardsHtml = `<div class="flex gap-2 mt-1">${this.renderHoleCards(playerHoleCards)}</div>`
      } else if (player.status === 'active' || player.status === 'all_in') {
        holeCardsHtml = `
          <div class="flex gap-2 mt-1">
            <div class="rounded border-2 border-white shadow-lg" style="width: 32px; height: 44px; background: linear-gradient(135deg, #10b981 0%, #065f46 100%);">
              <div class="w-full h-full flex items-center justify-center">
                <div class="w-5 h-7 border-2 border-white/60 rounded"></div>
              </div>
            </div>
            <div class="rounded border-2 border-white shadow-lg" style="width: 32px; height: 44px; background: linear-gradient(135deg, #10b981 0%, #065f46 100%);">
              <div class="w-full h-full flex items-center justify-center">
                <div class="w-5 h-7 border-2 border-white/60 rounded"></div>
              </div>
            </div>
          </div>
        `
      }

      const currentBetHtml = player.current_bet > 0 && !isFolded
        ? `<div class="mt-1 w-12 h-12 rounded-full flex items-center justify-center shadow-lg" style="background-color: #f59e0b;">
             <span class="text-white text-xs font-bold">${player.current_bet}</span>
           </div>`
        : ''

      return `
        <div class="absolute player-seat"
             style="top: ${pos.top}; left: ${pos.left}; transform: ${pos.transform};"
             data-position="${player.position}">
          <div class="flex flex-col items-center">
            <div class="relative">
              <div class="w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-sm shadow-lg ${avatarClass} ${isFolded ? 'opacity-50' : ''}">
                ${player.username.substring(0, 2).toUpperCase()}
              </div>
              ${isAllIn ? '<div class="absolute -bottom-1 left-1/2 -translate-x-1/2 px-1.5 py-0.5 bg-red-500 rounded-full text-[8px] font-bold text-white whitespace-nowrap">ALL IN</div>' : ''}
            </div>
            <div class="mt-1 text-center">
              <p class="text-white text-xs font-medium truncate max-w-[70px]">${player.username}</p>
              <p class="text-emerald-400 text-[10px] font-semibold">${player.chips.toLocaleString()}</p>
            </div>
            ${holeCardsHtml}
            ${currentBetHtml}
          </div>
        </div>
      `
    }).join("")
  }

  formatCard(card) {
    const rank = card[0]
    const suitChar = card[1]

    const letterToSymbol = { h: "♥", d: "♦", c: "♣", s: "♠" }
    const symbolColors = { "♥": "text-red-500", "♦": "text-red-500", "♣": "text-slate-900", "♠": "text-slate-900" }
    const letterColors = { h: "text-red-500", d: "text-red-500", c: "text-slate-900", s: "text-slate-900" }
    const rankNames = { T: "10", J: "J", Q: "Q", K: "K", A: "A" }

    let displaySuit, colorClass
    if (["♥", "♦", "♣", "♠"].includes(suitChar)) {
      displaySuit = suitChar
      colorClass = symbolColors[suitChar]
    } else {
      displaySuit = letterToSymbol[suitChar] || suitChar
      colorClass = letterColors[suitChar] || "text-slate-900"
    }

    const displayRank = rankNames[rank] || rank
    return { rank: displayRank, suit: displaySuit, colorClass }
  }

  formatRound(round) {
    const rounds = {
      preflop: "Pre-Flop",
      flop: "Flop",
      turn: "Turn",
      river: "River"
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

  showSuccess(message) {
    if (this.hasStatusMessageTarget) {
      this.statusMessageTarget.textContent = message
      this.statusMessageTarget.classList.remove("hidden", "text-red-600")
      this.statusMessageTarget.classList.add("text-emerald-400")

      setTimeout(() => {
        this.statusMessageTarget.classList.add("hidden")
      }, 3000)
    }
  }

  showWinnerAlert(winners) {
    const existingAlert = document.getElementById('winner-alert')
    if (existingAlert) return
    const alert = document.createElement('div')
    alert.id = 'winner-alert'
    alert.className = 'fixed top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 z-50 bg-black/90 backdrop-blur-xl rounded-2xl border-2 border-amber-500 p-8 min-w-[400px] text-center shadow-2xl'

    let winnerText = ''
    if (winners.length === 1) {
      winnerText = `
        <div class="text-4xl font-bold text-amber-400 mb-4">🏆 Winner!</div>
        <div class="text-2xl font-semibold text-white mb-2">${winners[0].username}</div>
        <div class="text-xl text-emerald-400 mb-2">$${winners[0].amount.toLocaleString()}</div>
        <div class="text-gray-300">${winners[0].hand_name}</div>
      `
    } else {
      const winnerNames = winners.map(w => w.username).join(' & ')
      winnerText = `
        <div class="text-4xl font-bold text-amber-400 mb-4">🏆 Split Pot!</div>
        <div class="text-2xl font-semibold text-white mb-2">${winnerNames}</div>
        <div class="text-xl text-emerald-400 mb-2">$${winners[0].amount.toLocaleString()} each</div>
        <div class="text-gray-300">${winners[0].hand_name}</div>
      `
    }

    alert.innerHTML = winnerText
    document.body.appendChild(alert)

    this.winnerAlertTimeout = setTimeout(() => {
      alert.remove()
    }, 4500)
  }

  startCountdown(seconds) {
    if (this.countdownInterval) {
      clearInterval(this.countdownInterval)
    }

    if (!this.hasCountdownTarget) return

    let timeLeft = seconds

    this.countdownTarget.classList.remove('hidden')
    this.countdownTarget.innerHTML = `
      <div class="text-amber-400 text-sm font-semibold">
        Next hand in ${timeLeft}s
      </div>
    `

    this.countdownInterval = setInterval(() => {
      timeLeft--

      if (timeLeft > 0) {
        this.countdownTarget.innerHTML = `
          <div class="text-amber-400 text-sm font-semibold">
            Next hand in ${timeLeft}s
          </div>
        `
      } else {
        clearInterval(this.countdownInterval)
        this.countdownInterval = null
        this.countdownTarget.classList.add('hidden')
        this.gameSubscription.perform("start_next_hand")
      }
    }, 1000)
  }

  showRebuyPrompt(game) {
    if (!this.hasActionButtonsTarget) return

    this.actionButtonsTarget.classList.remove('hidden')
    this.actionButtonsTarget.innerHTML = `
      <div class="bg-red-500/20 border-2 border-red-500 rounded-xl p-6">
        <h3 class="text-white text-xl font-bold mb-4 text-center">Out of Chips!</h3>
        <p class="text-white/80 text-sm mb-4 text-center">
          You need to rebuy to continue playing
        </p>
        <form data-action="submit->game#performRebuy" class="space-y-4">
          <div>
            <label class="text-white text-sm font-medium mb-2 block">Rebuy Amount</label>
            <input
              type="number"
              name="rebuy_amount"
              min="${game.min_buyin}"
              max="${game.max_buyin}"
              value="${game.min_buyin}"
              class="w-full px-4 py-2 bg-white/10 border border-white/20 rounded-lg text-white"
            >
            <p class="text-white/60 text-xs mt-1">Min: ${game.min_buyin} - Max: ${game.max_buyin}</p>
          </div>
          <div class="flex gap-3">
            <button
              type="submit"
              class="flex-1 px-6 py-3 bg-emerald-500 hover:bg-emerald-600 text-white font-bold rounded-lg transition"
            >
              Rebuy
            </button>
            <button
              type="button"
              data-action="click->game#leaveGame"
              class="flex-1 px-6 py-3 bg-gray-600 hover:bg-gray-700 text-white font-bold rounded-lg transition"
            >
              Leave Table
            </button>
          </div>
        </form>
      </div>
    `
  }

  startShowdownAutoAdvance() {
    console.log("Entering showdown mode - auto-advancing rounds every 3s")

    // Clear any existing timer
    this.stopShowdownAutoAdvance()

    // Start 3-second timer to advance rounds
    this.showdownTimer = setInterval(() => {
      if (this.gameSubscription) {
        this.gameSubscription.perform("advance_showdown_round", {})
      }
    }, 3000)
  }

  stopShowdownAutoAdvance() {
    if (this.showdownTimer) {
      clearInterval(this.showdownTimer)
      this.showdownTimer = null
    }
  }

  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }
}
