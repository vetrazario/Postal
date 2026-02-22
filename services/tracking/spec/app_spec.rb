# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe TrackingApp do
  describe 'GET /health' do
    it 'returns 200 with healthy status' do
      get '/health'

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)
      expect(json['status']).to eq('healthy')
      expect(json['timestamp']).to be_present
    end
  end

  describe 'GET /track/o' do
    it 'returns 404 when params are missing' do
      get '/track/o'

      expect(last_response.status).to eq(404)
    end

    it 'returns 404 when eid is missing' do
      cid = Base64.urlsafe_encode64('camp_1')
      mid = Base64.urlsafe_encode64('msg_1')
      get "/track/o?cid=#{cid}&mid=#{mid}"

      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /track/c' do
    it 'returns 404 when params are missing' do
      get '/track/c'

      expect(last_response.status).to eq(404)
    end

    it 'returns 404 for javascript: URL' do
      url = Base64.urlsafe_encode64('javascript:alert(1)')
      eid = Base64.urlsafe_encode64('user@example.com')
      cid = Base64.urlsafe_encode64('camp_1')
      mid = Base64.urlsafe_encode64('msg_1')

      get "/track/c?url=#{url}&eid=#{eid}&cid=#{cid}&mid=#{mid}"

      expect(last_response.status).to eq(404)
    end
  end

  describe 'GET /unsubscribe' do
    it 'returns 400 when eid is missing' do
      cid = Base64.urlsafe_encode64('camp_1')
      get "/unsubscribe?cid=#{cid}"

      expect(last_response.status).to eq(400)
    end
  end

  describe 'POST /unsubscribe' do
    it 'returns 400 when eid is missing' do
      post '/unsubscribe', { cid: Base64.urlsafe_encode64('camp_1') }

      expect(last_response.status).to eq(400)
      json = JSON.parse(last_response.body)
      expect(json['success']).to be false
    end
  end
end
