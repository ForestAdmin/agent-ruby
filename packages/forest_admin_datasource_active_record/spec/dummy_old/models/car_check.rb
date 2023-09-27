class CarCheck < ActiveRecord::Base
  belongs_to :car
  belongs_to :check
end
