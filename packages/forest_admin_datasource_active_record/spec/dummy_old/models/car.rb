class Car < ActiveRecord::Base
  belongs_to :category
  has_one :user
  has_many :car_checks
  has_many :checks, through: :car_checks
end
