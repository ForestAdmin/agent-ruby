class Address
  include Mongoid::Document
  field :street, type: String
  field :city, type: String
  field :zip_code, type: String

  embeds_one :meta, class_name: 'Meta'
  embedded_in :user
end
