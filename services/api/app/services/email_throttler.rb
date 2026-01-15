class EmailThrottler
  WARMUP_SCHEDULE = {
    1 => 10,   # Day 1: 10 emails
    2 => 15,   # Day 2: 15 emails
    3 => 20,   # Day 3: 20 emails
    4 => 30,   # Day 4: 30 emails
    5 => 40,   # Day 5: 40 emails
    6 => 50,   # Day 6: 50 emails
    7 => 75,   # Day 7: 75 emails
    14 => 100, # Day 14: 100 emails
    21 => 200, # Day 21: 200 emails
    30 => 500  # Day 30+: 500 emails (full capacity)
  }.freeze

  def self.can_send_email?
    return true unless warmup_mode?

    current_count = emails_sent_today
    limit = daily_limit

    current_count < limit
  end

  def self.remaining_quota
    return Float::INFINITY unless warmup_mode?

    limit = daily_limit
    current_count = emails_sent_today

    [limit - current_count, 0].max
  end

  def self.daily_limit
    if warmup_mode?
      warmup_daily_limit
    else
      SystemConfig.get(:daily_send_limit) || 500
    end
  end

  def self.warmup_mode?
    SystemConfig.get(:warmup_mode) == true
  end

  def self.warmup_daily_limit
    days_since_start = warmup_days_elapsed

    # Find applicable limit from schedule
    applicable_day = WARMUP_SCHEDULE.keys.sort.reverse.find { |day| days_since_start >= day }
    WARMUP_SCHEDULE[applicable_day] || 10
  end

  def self.warmup_days_elapsed
    warmup_start = SystemConfig.get(:warmup_start_date)
    return 0 unless warmup_start

    start_date = warmup_start.is_a?(String) ? Date.parse(warmup_start) : warmup_start.to_date
    (Date.current - start_date).to_i
  end

  def self.emails_sent_today
    EmailLog.where('created_at >= ?', Time.current.beginning_of_day)
            .where(status: ['sent', 'delivered', 'processing'])
            .count
  end

  def self.throttle_info
    {
      warmup_mode: warmup_mode?,
      daily_limit: daily_limit,
      emails_sent_today: emails_sent_today,
      remaining_quota: remaining_quota,
      can_send: can_send_email?,
      warmup_day: warmup_mode? ? warmup_days_elapsed : nil,
      next_limit_increase: warmup_mode? ? next_limit_increase_info : nil
    }
  end

  def self.next_limit_increase_info
    days = warmup_days_elapsed
    next_day = WARMUP_SCHEDULE.keys.sort.find { |d| d > days }

    return { message: 'Warmup complete!' } unless next_day

    {
      in_days: next_day - days,
      new_limit: WARMUP_SCHEDULE[next_day],
      current_limit: daily_limit
    }
  end

  # Enable warmup mode
  def self.enable_warmup!
    SystemConfig.set(:warmup_mode, true)
    SystemConfig.set(:warmup_start_date, Date.current.to_s) unless SystemConfig.get(:warmup_start_date)
    Rails.logger.info "Warmup mode enabled, starting from #{SystemConfig.get(:warmup_start_date)}"
  end

  # Disable warmup mode
  def self.disable_warmup!
    SystemConfig.set(:warmup_mode, false)
    Rails.logger.info "Warmup mode disabled"
  end
end
