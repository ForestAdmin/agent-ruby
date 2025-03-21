class Order < ActiveRecord::Base
  has_and_belongs_to_many :products
end
