class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher

  devise :database_authenticatable, :registerable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  enum :role, { reviewer: 0, admin: 1 }

  has_many :projects, dependent: :destroy
  has_many :submissions, dependent: :destroy

  validates :name, presence: true
end
