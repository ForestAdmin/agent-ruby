class TestDefault < ApplicationRecord
  enum :status, { inactive: 0, active: 1, archived: 2 }
  enum :priority, { low: 0, medium: 1, high: 2 }
end
