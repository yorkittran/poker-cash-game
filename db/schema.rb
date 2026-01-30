# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_01_30_043621) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "cash_sessions", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "user_id", null: false
    t.integer "buyin"
    t.integer "cashout"
    t.integer "profit_loss"
    t.integer "hands_played"
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_cash_sessions_on_game_id"
    t.index ["user_id"], name: "index_cash_sessions_on_user_id"
  end

  create_table "game_players", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "user_id", null: false
    t.integer "position"
    t.integer "chips"
    t.integer "buyin_amount"
    t.integer "cashout_amount"
    t.json "hole_cards"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "ready", default: false, null: false
    t.integer "current_bet", default: 0, null: false
    t.index ["game_id"], name: "index_game_players_on_game_id"
    t.index ["user_id"], name: "index_game_players_on_user_id"
  end

  create_table "games", force: :cascade do |t|
    t.string "name"
    t.integer "small_blind"
    t.integer "big_blind"
    t.integer "max_players"
    t.integer "min_buyin"
    t.integer "max_buyin"
    t.string "state"
    t.integer "current_hand_number"
    t.integer "dealer_position"
    t.integer "current_player_position"
    t.integer "pot"
    t.string "round"
    t.json "community_cards"
    t.text "deck_state"
    t.integer "created_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "showdown_mode", default: false, null: false
  end

  create_table "hands", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.integer "hand_number"
    t.integer "dealer_position"
    t.integer "small_blind"
    t.integer "big_blind"
    t.json "community_cards"
    t.integer "pot"
    t.json "winners"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "ended_by_showdown", default: false, null: false
    t.index ["game_id"], name: "index_hands_on_game_id"
  end

  create_table "player_actions", force: :cascade do |t|
    t.bigint "hand_id", null: false
    t.bigint "user_id", null: false
    t.string "action_type"
    t.integer "amount"
    t.string "round"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hand_id"], name: "index_player_actions_on_hand_id"
    t.index ["user_id"], name: "index_player_actions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "username", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.integer "total_bankroll", default: 10000, null: false
    t.integer "games_played", default: 0, null: false
    t.integer "hands_won", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "cash_sessions", "games"
  add_foreign_key "cash_sessions", "users"
  add_foreign_key "game_players", "games"
  add_foreign_key "game_players", "users"
  add_foreign_key "hands", "games"
  add_foreign_key "player_actions", "hands"
  add_foreign_key "player_actions", "users"
end
