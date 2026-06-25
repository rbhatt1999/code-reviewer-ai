require 'rails_helper'

# rspec-rails 6.1 registers ChannelExampleGroup for type: :channel only.
# ChannelExampleGroup includes both ActionCable::Connection::TestCase::Behavior
# and ActionCable::Channel::TestCase::Behavior, so `connect`, `connection`, and
# `have_rejected_connection` are all available here.
RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }

  # Mint a token of the same shape devise-jwt issues to clients.
  def jwt_for(user)
    token, _payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
    token
  end

  describe 'with a valid token' do
    it 'accepts the connection and identifies the user' do
      connect "/cable?token=#{jwt_for(user)}"
      expect(connection.current_user).to eq(user)
    end
  end

  describe 'with a missing token' do
    it 'rejects the connection' do
      expect { connect '/cable' }.to have_rejected_connection
    end
  end

  describe 'with an empty token' do
    it 'rejects the connection' do
      expect { connect '/cable?token=' }.to have_rejected_connection
    end
  end

  describe 'with an invalid token' do
    it 'rejects the connection' do
      expect { connect '/cable?token=not.a.real.jwt' }.to have_rejected_connection
    end
  end

  describe 'with a token signed with a different secret' do
    it 'rejects the connection' do
      bad_token = JWT.encode({ sub: user.id }, 'wrong_secret', 'HS256')
      expect { connect "/cable?token=#{bad_token}" }.to have_rejected_connection
    end
  end
end
