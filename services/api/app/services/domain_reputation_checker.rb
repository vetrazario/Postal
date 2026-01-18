class DomainReputationChecker
  attr_reader :domain

  BLACKLISTS = [
    'zen.spamhaus.org',
    'bl.spamcop.net',
    'dnsbl.sorbs.net',
    'b.barracudacentral.org'
  ].freeze

  def initialize(domain = nil)
    @domain = domain || SystemConfig.get(:domain) || 'localhost'
  end

  # Full reputation check
  def check_all
    {
      domain: domain,
      spf: check_spf,
      dkim: check_dkim,
      dmarc: check_dmarc,
      blacklists: check_blacklists,
      mx_records: check_mx,
      reputation_score: calculate_score,
      recommendations: generate_recommendations
    }
  end

  # Check SPF record
  def check_spf
    result = dns_lookup("#{domain}", 'TXT')
    spf_record = result.find { |r| r.start_with?('v=spf1') }

    {
      exists: spf_record.present?,
      record: spf_record,
      valid: spf_record.present? && spf_record.include?('~all') || spf_record.include?('-all')
    }
  rescue StandardError => e
    { exists: false, error: e.message }
  end

  # Check DKIM (requires selector, check common ones)
  def check_dkim
    selectors = ['default', 'postal', 'mail', 'dkim']
    found_records = []

    selectors.each do |selector|
      result = dns_lookup("#{selector}._domainkey.#{domain}", 'TXT')
      dkim_record = result.find { |r| r.include?('v=DKIM1') }
      found_records << { selector: selector, record: dkim_record } if dkim_record
    end

    {
      exists: found_records.any?,
      records: found_records,
      selectors_checked: selectors
    }
  rescue StandardError => e
    { exists: false, error: e.message }
  end

  # Check DMARC record
  def check_dmarc
    result = dns_lookup("_dmarc.#{domain}", 'TXT')
    dmarc_record = result.find { |r| r.start_with?('v=DMARC1') }

    policy = extract_dmarc_policy(dmarc_record) if dmarc_record

    {
      exists: dmarc_record.present?,
      record: dmarc_record,
      policy: policy,
      valid: dmarc_record.present? && ['quarantine', 'reject'].include?(policy)
    }
  rescue StandardError => e
    { exists: false, error: e.message }
  end

  # Check if domain/IP is in blacklists
  def check_blacklists
    ip_address = get_server_ip
    return { error: 'Could not determine server IP' } unless ip_address

    reversed_ip = ip_address.split('.').reverse.join('.')
    results = {}

    BLACKLISTS.each do |blacklist|
      listed = dns_exists?("#{reversed_ip}.#{blacklist}")
      results[blacklist] = {
        listed: listed,
        status: listed ? 'BLACKLISTED' : 'OK'
      }
    end

    {
      ip_address: ip_address,
      checks: results,
      blacklisted: results.values.any? { |r| r[:listed] }
    }
  rescue StandardError => e
    { error: e.message }
  end

  # Check MX records
  def check_mx
    result = dns_lookup(domain, 'MX')
    mx_records = result.map { |r| r.split(' ').last }

    {
      exists: mx_records.any?,
      records: mx_records,
      count: mx_records.size
    }
  rescue StandardError => e
    { exists: false, error: e.message }
  end

  # Calculate reputation score (0-100)
  def calculate_score
    score = 0

    # SPF (25 points)
    spf = check_spf
    score += 25 if spf[:valid]
    score += 10 if spf[:exists] && !spf[:valid]

    # DKIM (25 points)
    dkim = check_dkim
    score += 25 if dkim[:exists]

    # DMARC (25 points)
    dmarc = check_dmarc
    score += 25 if dmarc[:valid]
    score += 10 if dmarc[:exists] && !dmarc[:valid]

    # Blacklists (25 points)
    blacklists = check_blacklists
    score += 25 unless blacklists[:blacklisted]

    score
  end

  # Generate recommendations
  def generate_recommendations
    recommendations = []

    spf = check_spf
    recommendations << 'Add SPF record to your domain' unless spf[:exists]
    recommendations << 'SPF record should use ~all or -all policy' if spf[:exists] && !spf[:valid]

    dkim = check_dkim
    recommendations << 'Configure DKIM signing for your emails' unless dkim[:exists]

    dmarc = check_dmarc
    recommendations << 'Add DMARC record to your domain' unless dmarc[:exists]
    recommendations << 'DMARC policy should be quarantine or reject' if dmarc[:exists] && !dmarc[:valid]

    blacklists = check_blacklists
    if blacklists[:blacklisted]
      listed = blacklists[:checks].select { |_, v| v[:listed] }.keys
      recommendations << "Your IP is blacklisted on: #{listed.join(', ')}. Request delisting."
    end

    mx = check_mx
    recommendations << 'Add MX records to your domain' unless mx[:exists]

    recommendations << 'All checks passed! ✓' if recommendations.empty?

    recommendations
  end

  private

  def dns_lookup(name, type)
    result = `dig +short #{type} #{name} 2>/dev/null`.split("\n").map(&:strip).reject(&:empty?)
    result.map { |r| r.gsub(/"/, '') } # Remove quotes from TXT records
  end

  def dns_exists?(name)
    result = `dig +short #{name} 2>/dev/null`.strip
    result.present?
  end

  def get_server_ip
    # Try to get public IP
    ip = `curl -s ifconfig.me 2>/dev/null`.strip
    return ip if ip.present? && ip.match?(/^\d+\.\d+\.\d+\.\d+$/)

    # Fallback: get IP from domain
    result = dns_lookup(domain, 'A')
    result.first
  end

  def extract_dmarc_policy(record)
    match = record.match(/p=(none|quarantine|reject)/)
    match[1] if match
  end
end
