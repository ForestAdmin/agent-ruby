module Api
  class Note < ApplicationRecord
    # legacy/demodulized polymorphic types: the column stores "Topic", not "Api::Topic"
    self.store_full_class_name = false
    belongs_to :notable, polymorphic: true, optional: true
  end
end
