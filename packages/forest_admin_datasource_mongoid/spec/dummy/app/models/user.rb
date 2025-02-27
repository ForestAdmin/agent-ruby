class User
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  belongs_to :item, polymorphic: true
  embeds_many :addresses
  embeds_one :address
end
