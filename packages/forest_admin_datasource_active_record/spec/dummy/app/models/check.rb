class Check < ApplicationRecord
  has_many :car_checks
  has_many :cars, through: :car_checks
end
