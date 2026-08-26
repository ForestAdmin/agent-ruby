class Box < ApplicationRecord
  has_many :slots
  has_many :tags, through: :slots
end
