class User < ApplicationRecord
  belongs_to :car
  has_one :address, as: :addressable

  enum :enum_field, { draft: 0, published: 1, archived: 2, trashed: 3 }
end
