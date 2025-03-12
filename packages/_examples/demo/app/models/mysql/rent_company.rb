module Mysql
  class RentCompany < MysqlDbRecord
    has_many :cars
  end
end
