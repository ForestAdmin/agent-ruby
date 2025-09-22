module Mysql
  class MysqlDbRecord < ApplicationRecord
    self.abstract_class = true

    connects_to database: { writing: :mysql_db, reading: :mysql_db }
  end
end
