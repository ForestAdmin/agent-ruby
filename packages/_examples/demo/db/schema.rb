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

ActiveRecord::Schema[8.0].define(version: 2025_03_11_103551) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "bookings", force: :cascade do |t|
    t.bigint "car_id", null: false
    t.integer "customer_id"
    t.datetime "start_date"
    t.datetime "end_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["car_id"], name: "index_bookings_on_car_id"
  end

  create_table "cars", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.string "reference"
    t.string "model"
    t.string "brand"
    t.integer "year"
    t.integer "nb_seats"
    t.boolean "is_manual"
    t.json "options"
    t.integer "rent_company_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_cars_on_category_id"
  end

  create_table "cars_checks", force: :cascade do |t|
    t.bigint "car_id", null: false
    t.bigint "check_id", null: false
    t.index ["car_id"], name: "index_cars_checks_on_car_id"
    t.index ["check_id"], name: "index_cars_checks_on_check_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "checks", force: :cascade do |t|
    t.string "garage_name"
    t.date "date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "firstname"
    t.string "lastname"
    t.string "email"
    t.string "password"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "bookings", "cars"
  add_foreign_key "cars", "categories"
  add_foreign_key "cars_checks", "cars"
  add_foreign_key "cars_checks", "checks"
end
