User.find_or_create_by!(email: 'admin@example.com') do |u|
  u.password = 'password1234'
  u.name = 'Admin'
  u.role = :admin
end

demo = User.find_or_create_by!(email: 'demo@example.com') do |u|
  u.password = 'password1234'
  u.name = 'Demo Reviewer'
end

Project.find_or_create_by!(user: demo, name: 'demo-ruby-app') do |p|
  p.language = 'ruby'
  p.default_branch = 'main'
end

Rails.logger.debug 'Seeded admin@example.com / demo@example.com (password: password1234)'
