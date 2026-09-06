# src/report_builder.rb
require 'json'
require_relative 'config'

module ReportBuilder
  extend self

  def build(decisions, providers, history)
    distribution = build_distribution(decisions, providers)
    skip_reasons = build_skip_reasons(decisions)
    projected_util = build_projected_utilization(providers)
    recommendations = build_recommendations(decisions, providers, history)

    {
      'period' => Time.now.strftime('%Y-%m-%d'),
      'total_operations' => decisions.size,
      'distribution' => distribution,
      'skip_reasons' => skip_reasons,
      'projected_daily_utilization' => projected_util,
      'recommendations' => recommendations
    }
  end

  private

  def build_distribution(decisions, providers)
    dist = {}
    decisions.each do |dec|
      ps = dec['selected_provider']
      next if ps.nil?
      dist[ps] ||= { 'count' => 0 }
      dist[ps]['count'] += 1
    end
    total = decisions.size
    dist.each do |ps, data|
      data['share_pct'] = (data['count'].to_f / total * 100).round(2)
      provider = providers.find { |p| p.payment_system == ps }
      data['target_pct'] = provider ? provider.traffic_percentage : 0
    end
    dist
  end

  def build_skip_reasons(decisions)
    reasons = {}
    decisions.each do |dec|
      dec['attempts'].each do |attempt|
        next if attempt['decision'] == 'selected'
        reason = attempt['reason']
        reasons[reason] ||= 0
        reasons[reason] += 1
      end
    end
    reasons
  end

  def build_projected_utilization(providers)
    util = {}
    providers.each do |p|
      util[p.payment_system] = {
        'used' => p.daily_approved_amount.round(2),
        'limit' => p.daily_amount_limit == Float::INFINITY ? nil : p.daily_amount_limit,
        'utilization_pct' => p.daily_amount_limit == Float::INFINITY ? nil : (p.daily_approved_amount / p.daily_amount_limit * 100).round(2)
      }
    end
    util
  end

  def build_recommendations(decisions, providers, history)
    recs = []

    # Рекомендации по долям
    history.each do |ps, hist|
      target = providers.find { |p| p.payment_system == ps }&.traffic_percentage || 0
      actual = hist[:count_share] * 100
      diff = (actual - target).abs
      if diff > 5
        if actual > target
          recs << "#{ps} получает #{actual.round(1)}% трафика при цели #{target}% — рекомендуется снизить traffic_percentage"
        else
          recs << "#{ps} получает #{actual.round(1)}% трафика при цели #{target}% — рекомендуется повысить traffic_percentage"
        end
      end
      if hist[:conversion] < 0.7
        recs << "#{ps} имеет низкую конверсию (#{(hist[:conversion]*100).round(1)}%) — рассмотрите снижение трафика или улучшение качества"
      end
    end

    # Рекомендации по лимитам
    providers.each do |p|
      if p.daily_amount_limit < Float::INFINITY && p.daily_approved_amount / p.daily_amount_limit > 0.8
        recs << "#{p.payment_system} близок к дневному лимиту (#{p.daily_approved_amount}/#{p.daily_amount_limit}) — снизить трафик или увеличить лимит"
      end
    end

    recs
  end
end