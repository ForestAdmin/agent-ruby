class Leaf < ApplicationRecord
  belongs_to :child, foreign_key: :custom_child_id, inverse_of: :leaf
end
