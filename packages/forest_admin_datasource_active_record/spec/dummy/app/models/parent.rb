class Parent < ApplicationRecord
  has_many :kids, as: :owner
  has_many :details, through: :kids, source: :detail
end
