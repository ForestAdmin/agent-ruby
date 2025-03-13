class Car < ApplicationRecord
  belongs_to :rent_company, class_name: 'Mysql::RentCompany'
  belongs_to :category
  has_many :bookings
  # has_many :car_checks
  # has_many :checks, through: :car_checks
  has_and_belongs_to_many :checks
end
