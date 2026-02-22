# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Unsubscribe', type: :request do
  describe 'GET /unsubscribe' do
    it 'returns 200 with unsubscribe page when valid params' do
      eid = Base64.urlsafe_encode64('user@example.com')
      cid = Base64.urlsafe_encode64('camp_123')

      get "/unsubscribe?eid=#{eid}&cid=#{cid}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Unsubscribe').or include('unsubscribe').or include('Отписаться')
    end

    it 'handles missing params' do
      get '/unsubscribe'

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /unsubscribe' do
    it 'records unsubscribe and redirects when valid params' do
      eid = Base64.urlsafe_encode64('newuser@example.com')
      cid = Base64.urlsafe_encode64('camp_456')

      expect {
        post "/unsubscribe?eid=#{eid}&cid=#{cid}", headers: { 'HTTP_HOST' => 'test.host' }
      }.to change(Unsubscribe, :count).by(2) # campaign-specific + global

      expect(response).to have_http_status(:found)
      expect(Unsubscribe.blocked?(email: 'newuser@example.com', campaign_id: 'camp_456')).to be true
    end

    it 'returns 400 for one-click when email is missing' do
      post '/unsubscribe', params: { 'List-Unsubscribe' => 'One-Click' }

      expect(response).to have_http_status(:bad_request)
    end

    it 'returns 200 for one-click when valid' do
      eid = Base64.urlsafe_encode64('oneclick@example.com')
      cid = Base64.urlsafe_encode64('camp_789')

      post "/unsubscribe?eid=#{eid}&cid=#{cid}", params: { 'List-Unsubscribe' => 'One-Click' }

      expect(response).to have_http_status(:ok)
      expect(Unsubscribe.blocked?(email: 'oneclick@example.com', campaign_id: 'camp_789')).to be true
    end
  end
end
