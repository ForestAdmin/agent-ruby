class Category < ApplicationRecord
  has_one :fake

  def fake
    { id: 1, label: 'fake association' }
  end
end
