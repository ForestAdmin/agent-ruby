class Departure
  include Mongoid::Document
  include Mongoid::Timestamps
  field :label, type: String

  has_one :user, as: :item
end
