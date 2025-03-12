require './db/mongo_seeds'

# destroy all rows
Booking.destroy_all
Check.destroy_all
Car.destroy_all
User.destroy_all
Category.destroy_all
Mysql::Customer.destroy_all
Mysql::RentCompany.destroy_all


Category.create! label: 'SUV'
Category.create! label: 'Convertible'
Category.create! label: 'Coupe'
Category.create! label: 'Wagon'
Category.create! label: 'Sports car'
categories = Category.all


Mysql::RentCompany.create!(name: 'Hertz')
Mysql::RentCompany.create!(name: 'Europcar')
Mysql::RentCompany.create!(name: 'Sixt')
companies = Mysql::RentCompany.all

30.times do
  Mysql::Customer.create!(firstname: Faker::Name.first_name, lastname: Faker::Name.last_name)

  Car.create!(
    category_id: categories.sample.id,
    reference: Faker::Vehicle.vin,
    model: Faker::Vehicle.model,
    brand: Faker::Vehicle.manufacture,
    year: Faker::Number.between(from: 1995, to: 2023),
    nb_seats: Faker::Number.between(from: 2, to: 9),
    is_manual: Faker::Boolean.boolean,
    options: Faker::Vehicle.car_options,
    rent_company_id: companies.sample.id
  )

  Check.create!(
    garage_name: "garage #{Faker::Vehicle.manufacture}",
    date: Faker::Date.between(from: '2022-01-01', to: '2024-01-01')
  )
end

customers = Mysql::Customer.all
cars = Car.all
30.times do
  start_date = Faker::Date.between(from: '2022-01-01', to: '2025-01-01')
  end_date = Faker::Date.between(from: start_date, to: '2025-01-02')
  Booking.create!(
    customer_id: customers.sample.id,
    car_id: cars.sample.id,
    start_date: start_date,
    end_date: end_date
  )
end

30.times do
  User.create!(
    firstname: Faker::Name.first_name,
    lastname: Faker::Name.last_name,
    email: Faker::Internet.email,
    password: '111111'
  )
end
