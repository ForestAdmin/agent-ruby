class Booking < ApplicationRecord
  belongs_to :customer, class_name: 'Mysql::Customer'
  belongs_to :car
end
