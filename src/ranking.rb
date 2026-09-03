require_relative 'provider'

# Веса по умолчанию (сумма может быть ≠ 1, но для удобства приведена к 1)
DEFAULT_RANKING_WEIGHTS = {
  traffic: 0.25,       # отклонение по количеству
  volume: 0.25,        # отклонение по объёму
  conversion: 0.15,    # конверсия
  priority: 0.10,      # приоритет (инвертированный)
  turnover_min: 0.10,  # недобор минимального оборота
  turnover_max: 0.05,  # превышение максимального оборота (штраф)
  utilization: 0.10    # загрузка дневного лимита (штраф)
}.freeze

def rank_providers(providers, operation, weights = {}, global_stats = {})
  weights = DEFAULT_RANKING_WEIGHTS.merge(weights.transform_keys(&:to_sym))
  amount = operation['amount'].to_f

  total_count = global_stats[:total_approved_count] || 1
  total_amount = global_stats[:total_approved_amount] || 1.0

  providers.map do |provider|
    p = provider.is_a?(Provider) ? provider : Provider.new(provider)

    unless p.respond_to?(:daily_approved_count)
      warn "Provider #{p.id} does not have daily_approved_count – using 0"
      p.instance_variable_set(:@daily_approved_count, 0) if p.instance_variable_defined?(:@daily_approved_count)
    end

    score = 0.0
    details = {}

    if weights[:traffic] > 0
      target = p.traffic_percentage / 100.0
      current = p.daily_approved_count.to_f / total_count
      deviation = (target - current).clamp(-1, 1)
      score += deviation * weights[:traffic]
      details[:traffic] = { target: target, current: current, deviation: deviation }
    end

    if weights[:volume] > 0
      target = p.volume_share_pct / 100.0
      current = p.daily_approved_amount / total_amount
      deviation = (target - current).clamp(-1, 1)
      score += deviation * weights[:volume]
      details[:volume] = { target: target, current: current, deviation: deviation }
    end

    if weights[:conversion] > 0
      score += p.conversion_24h * weights[:conversion]
      details[:conversion] = p.conversion_24h
    end

    if weights[:priority] > 0
      priority_score = 1.0 / (p.priority + 1)
      score += priority_score * weights[:priority]
      details[:priority] = { raw: p.priority, normalized: priority_score }
    end

    if weights[:turnover_min] > 0 && p.daily_turnover_min > 0
      projected = p.daily_approved_amount + amount
      if projected < p.daily_turnover_min
        deficit = 1.0 - projected / p.daily_turnover_min
        score += deficit * weights[:turnover_min]
        details[:turnover_min] = { target: p.daily_turnover_min, projected: projected, deficit: deficit }
      else
        details[:turnover_min] = { target: p.daily_turnover_min, projected: projected, deficit: 0 }
      end
    end

    if weights[:turnover_max] > 0 && p.daily_turnover_max < Float::INFINITY
      projected = p.daily_approved_amount + amount
      if projected > p.daily_turnover_max
        excess = (projected - p.daily_turnover_max) / p.daily_turnover_max
        excess = [excess, 1.0].min
        score -= excess * weights[:turnover_max]
        details[:turnover_max] = { limit: p.daily_turnover_max, projected: projected, excess: excess }
      else
        details[:turnover_max] = { limit: p.daily_turnover_max, projected: projected, excess: 0 }
      end
    end

    if weights[:utilization] > 0 && p.daily_amount_limit < Float::INFINITY
      projected_util = (p.daily_approved_amount + amount) / p.daily_amount_limit
      projected_util = projected_util.clamp(0, 1)
      penalty = projected_util ** 2
      score -= penalty * weights[:utilization]
      details[:utilization] = { limit: p.daily_amount_limit, projected_util: projected_util, penalty: penalty }
    end

    { provider: p, score: score.round(6), details: details }
  end.sort_by { |item| -item[:score] }
end

def best_provider(providers, operation, weights = {}, global_stats = {})
  ranked = rank_providers(providers, operation, weights, global_stats)
  ranked.first&.fetch(:provider)
end
