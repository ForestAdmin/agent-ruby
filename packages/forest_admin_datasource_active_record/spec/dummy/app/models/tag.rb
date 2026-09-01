class Tag < ApplicationRecord
  belongs_to :slot, foreign_key: :custom_slot_id, inverse_of: :tag
end
