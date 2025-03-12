# destroy all rows
Product.destroy_all
Manufacturer.destroy_all

Manufacturer.create!(name: Faker::Commerce.brand, siren: Faker::Code.asin)
Manufacturer.create!(name: Faker::Commerce.brand, siren: Faker::Code.asin)
Manufacturer.create!(name: Faker::Commerce.brand, siren: Faker::Code.asin)

manufacturers = Manufacturer.all
30.times do
  Product.create!(
    label: Faker::Commerce.product_name,
    quantity: Faker::Number.number(digits: 3),
    next_restocking_date: Faker::Date.between(from: Date.today, to: 2.months.after),
    manufacturer_id: manufacturers.sample.id
  )
end
