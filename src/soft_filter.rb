require_relative 'provider'

class SoftFilter
  DEFAULT_STRATEGY_WEIGHTS = {
    traffic: 0.20,
    volume: 0.20,
    conversion: 0.20,
    priority: 0.10,
    turnover_min: 0.10,
    turnover_max: 0.10,
    amount_fit: 0.05,
    current_load: 0.05
  }.freeze

  def self.score_providers(providers, operation, weights = {}, global_stats = {})
    weights = DEFAULT_STRATEGY_WEIGHTS.merge(weights.transform_keys(&:to_sym))
    amount = operation['amount'].to_f

    total_count = global_stats[:total_approved_count] || 1
    total_amount = global_stats[:total_approved_amount] || 1.0
    total_count = 1 if total_count == 0
    total_amount = 1.0 if total_amount == 0.0

    providers.map do |provider|
      p = provider.is_a?(Provider) ? provider : Provider.new(provider)
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
        norm_priority = 1.0 / (p.priority + 1)
        score += norm_priority * weights[:priority]
        details[:priority] = { raw: p.priority, normalized: norm_priority }
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

      # --- Новый фактор: насколько сумма близка к центру диапазона провайдера ---
      if weights[:amount_fit] > 0
        min = p.limit_amount_min
        max = p.limit_amount_max
        if max < Float::INFINITY && min < max
          center = (min + max) / 2.0
          half_range = (max - min) / 2.0
          if half_range > 0
            distance_from_center = (amount - center).abs / half_range
            fit = 1.0 - [distance_from_center, 1.0].min
            score += fit * weights[:amount_fit]
            details[:amount_fit] = { fit: fit.round(4) }
          end
        end
      end

      # --- Новый фактор: штраф за высокую текущую загрузку (in-progress) ---
      if weights[:current_load] > 0
        in_progress = p.in_progress_count
        limit = p.in_progress_count_limit
        if limit < Float::INFINITY && limit > 0
          load_ratio = in_progress.to_f / limit
          penalty = load_ratio ** 2
          score -= penalty * weights[:current_load]
          details[:current_load] = { load_ratio: load_ratio.round(4), penalty: penalty.round(4) }
        end
      end

      { provider: p, score: score.round(6), details: details }
    end.sort_by { |item| -item[:score] }
  end

  def self.best_provider(providers, operation, weights = {}, global_stats = {})
    scored = score_providers(providers, operation, weights, global_stats)
    return nil if scored.empty?

    best_score = scored.first[:score]
    candidates = scored.select { |item| item[:score] == best_score }
    candidates.min_by { |item| item[:provider].priority }[:provider]
  end
end