class Child < ApplicationRecord
  belongs_to :owner, polymorphic: true
  has_one :leaf, foreign_key: :custom_child_id, inverse_of: :child
end
