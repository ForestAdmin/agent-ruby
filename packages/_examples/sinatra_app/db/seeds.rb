require 'faker'
require_relative '../app'

# Clean db
Product.destroy_all
Order.destroy_all
Category.destroy_all

cat_console = Category.create! label: 'Console'
cat_game = Category.create! label: 'Video game'
cat_camera = Category.create! label: 'Camera'

Product.create!(category_id: cat_console.id, name: 'PS5', description: Faker::Lorem.words, price: Faker::Number.decimal(l_digits: 3))
Product.create!(category_id: cat_console.id, name: 'Xbox', description: Faker::Lorem.words, price: Faker::Number.decimal(l_digits: 3))
Product.create!(category_id: cat_game.id, name: Faker::Game.title, description: Faker::Lorem.words, price: Faker::Number.decimal(l_digits: 2))
Product.create!(category_id: cat_game.id, name: Faker::Game.title, description: Faker::Lorem.words, price: Faker::Number.decimal(l_digits: 2))
Product.create!(category_id: cat_game.id, name: Faker::Game.title, description: Faker::Lorem.words, price: Faker::Number.decimal(l_digits: 2))
Product.create!(category_id: cat_game.id, name: Faker::Game.title, description: Faker::Lorem.words, price: Faker::Number.decimal(l_digits: 2))
Product.create!(category_id: cat_game.id, name: Faker::Game.title, description: Faker::Lorem.words, price: Faker::Number.decimal(l_digits: 2))
Product.create!(category_id: cat_camera.id, name: Faker::Camera.brand_with_model, description: Faker::Lorem.words, price: Faker::Number.decimal(l_digits: 3))

products = Product.all
30.times do
  order = Order.create!(
    reference: Faker::Code.asin,
    total: Faker::Number.decimal(l_digits: Faker::Number.between(from: 2, to: 5)),
    shipping_costs: Faker::Number.decimal(l_digits: 2),
    status: 'WIP'
  )

  order.products << products.sample
end
