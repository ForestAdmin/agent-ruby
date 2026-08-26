class Parent < ApplicationRecord
  has_many :children, as: :owner
  has_many :leaves, through: :children
end
