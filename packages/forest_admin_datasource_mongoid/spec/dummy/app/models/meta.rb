class Meta
  include Mongoid::Document
  field :length, type: String

  embedded_in :address
end
