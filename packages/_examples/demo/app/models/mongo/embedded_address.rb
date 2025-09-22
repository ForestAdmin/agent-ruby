module Mongo
  class EmbeddedAddress
    include Mongoid::Document
    field :street, type: String
    field :city, type: String
    field :zip_code, type: String

    embedded_in :user, class_name: 'Mongo::User'
  end
end
