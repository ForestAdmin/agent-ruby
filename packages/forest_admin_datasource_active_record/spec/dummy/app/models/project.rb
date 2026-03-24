class Project < ApplicationRecord
  has_many :members, as: :memberable, dependent: :destroy
  has_many :users, through: :members, source: :user
end
