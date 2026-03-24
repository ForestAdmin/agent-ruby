class User < ApplicationRecord
  belongs_to :car
  has_one :address, as: :addressable
  has_and_belongs_to_many :companies
  has_many :members, dependent: :destroy
  has_many :projects, through: :members, source: :memberable, source_type: 'Project'

  enum :enum_field, { draft: 0, published: 1, archived: 2, trashed: 3 }
end
