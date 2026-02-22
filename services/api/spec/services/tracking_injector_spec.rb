# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrackingInjector do
  let(:recipient) { 'user@example.com' }
  let(:campaign_id) { 'camp_123' }
  let(:message_id) { 'msg_456' }
  let(:domain) { 'track.example.com' }

  describe '.inject_tracking_links' do
    it 'replaces http links with tracking URLs' do
      html = '<a href="https://example.com/page">Click</a>'

      result = TrackingInjector.inject_tracking_links(
        html: html,
        recipient: recipient,
        campaign_id: campaign_id,
        message_id: message_id,
        domain: domain
      )

      expect(result).to include('/track/c?url=')
      expect(result).to include('eid=')
      expect(result).to include('cid=')
      expect(result).to include('mid=')
      expect(result).to include(domain)
    end

    it 'skips mailto links' do
      html = '<a href="mailto:test@example.com">Email</a>'

      result = TrackingInjector.inject_tracking_links(
        html: html,
        recipient: recipient,
        campaign_id: campaign_id,
        message_id: message_id,
        domain: domain
      )

      expect(result).to eq(html)
    end

    it 'skips anchor links' do
      html = '<a href="#section">Anchor</a>'

      result = TrackingInjector.inject_tracking_links(
        html: html,
        recipient: recipient,
        campaign_id: campaign_id,
        message_id: message_id,
        domain: domain
      )

      expect(result).to eq(html)
    end

    it 'skips unsubscribe links' do
      html = '<a href="https://example.com/unsubscribe?id=1">Unsubscribe</a>'

      result = TrackingInjector.inject_tracking_links(
        html: html,
        recipient: recipient,
        campaign_id: campaign_id,
        message_id: message_id,
        domain: domain
      )

      expect(result).to eq(html)
    end

    it 'skips links that already use tracking domain' do
      html = "<a href=\"https://#{domain}/track/c?url=abc\">Link</a>"

      result = TrackingInjector.inject_tracking_links(
        html: html,
        recipient: recipient,
        campaign_id: campaign_id,
        message_id: message_id,
        domain: domain
      )

      expect(result).to eq(html)
    end

    it 'returns html unchanged when required params are blank' do
      html = '<a href="https://example.com">Link</a>'

      result = TrackingInjector.inject_tracking_links(
        html: html,
        recipient: '',
        campaign_id: campaign_id,
        message_id: message_id,
        domain: domain
      )

      expect(result).to eq(html)
    end
  end

  describe '.inject_tracking_pixel' do
    it 'inserts pixel before </body>' do
      html = '<html><body><p>Content</p></body></html>'

      result = TrackingInjector.inject_tracking_pixel(
        html: html,
        recipient: recipient,
        campaign_id: campaign_id,
        message_id: message_id,
        domain: domain
      )

      expect(result).to include('<img src=')
      expect(result).to include('/track/o?')
      expect(result).to include('eid=')
      expect(result).to include('</body>')
    end

    it 'appends pixel when no </body> tag' do
      html = '<html><p>Content</p></html>'

      result = TrackingInjector.inject_tracking_pixel(
        html: html,
        recipient: recipient,
        campaign_id: campaign_id,
        message_id: message_id,
        domain: domain
      )

      expect(result).to end_with('</html>')
      expect(result).to include('/track/o?')
    end

    it 'returns html unchanged when required params are blank' do
      html = '<html><body></body></html>'

      result = TrackingInjector.inject_tracking_pixel(
        html: html,
        recipient: recipient,
        campaign_id: '',
        message_id: message_id,
        domain: domain
      )

      expect(result).to eq(html)
    end
  end

  describe '.inject_unsubscribe_footer' do
    it 'inserts footer before </body>' do
      html = '<html><body><p>Content</p></body></html>'

      result = TrackingInjector.inject_unsubscribe_footer(
        html: html,
        recipient: recipient,
        campaign_id: campaign_id,
        domain: domain
      )

      expect(result).to include('Отписаться от рассылки')
      expect(result).to include('/unsubscribe?')
      expect(result).to include('eid=')
      expect(result).to include('cid=')
    end
  end

  describe '.inject_all' do
    it 'injects links, pixel, and footer' do
      html = '<html><body><a href="https://example.com">Link</a></body></html>'

      result = TrackingInjector.inject_all(
        html: html,
        recipient: recipient,
        campaign_id: campaign_id,
        message_id: message_id,
        domain: domain
      )

      expect(result).to include('/track/c?')
      expect(result).to include('/track/o?')
      expect(result).to include('Отписаться от рассылки')
    end
  end
end
