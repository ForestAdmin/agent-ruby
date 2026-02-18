class User < ApplicationRecord
  enum :status, { inactive: 0, active: 1, archived: 2 }
  enum :role, { user: 0, admin: 1, moderator: 2 }
end
