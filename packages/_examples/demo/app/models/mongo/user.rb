module Mongo
  class User
    include Mongoid::Document
    include Mongoid::Timestamps

    field :name, type: String
    belongs_to :item, polymorphic: true
    embeds_many :addresses, class_name: 'Mongo::EmbeddedAddress'
  end
end
