FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    password { 'password123' }
    role { :reviewer }

    trait :admin do
      role { :admin }
    end
  end
end
