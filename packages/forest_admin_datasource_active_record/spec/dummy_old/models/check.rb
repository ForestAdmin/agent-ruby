class Check < ActiveRecord::Base
  has_many :car_checks
  has_many :cars, through: :car_checks
end
