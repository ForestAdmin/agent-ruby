class Slot < ApplicationRecord
  belongs_to :box
  has_one :tag, foreign_key: :custom_slot_id, inverse_of: :slot
end
