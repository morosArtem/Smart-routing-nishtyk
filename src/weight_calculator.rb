# src/weight_calculator.rb
require_relative 'config'

module WeightCalculator
  extend self

  def compute(history, providers_data)
    # Если история пуста – возвращаем базовые веса
    return Config::DEFAULT_WEIGHTS.dup if history.empty?

    # --- Анализ конверсий ---
    conversions = history.values.map { |h| h[:conversion] }.compact
    avg_conversion = conversions.sum / conversions.size if conversions.any?
    std_dev = Math.sqrt(conversions.map { |c| (c - avg_conversion) ** 2 }.sum / conversions.size) if conversions.size > 1

    conversion_weight = 0.20
    if avg_conversion && avg_conversion > 0.85
      conversion_weight = 0.10          # все провайдеры надёжны – снижаем важность
    elsif std_dev && std_dev > 0.15
      conversion_weight = 0.30          # большой разброс – повышаем важность
    end

    # --- Анализ отклонения долей ---
    deviations = []
    providers_data.each do |p|
      ps = p['payment_system']
      hist = history[ps]
      next unless hist
      target_traffic = p['traffic_percentage'].to_f / 100.0
      actual_traffic = hist[:count_share] || 0
      deviations << (target_traffic - actual_traffic).abs
    end
    avg_deviation = deviations.any? ? deviations.sum / deviations.size : 0

    traffic_volume_weight = 0.20
    if avg_deviation > 0.10
      traffic_volume_weight = 0.30      # большие отклонения – активнее корректируем
    elsif avg_deviation < 0.03
      traffic_volume_weight = 0.15      # уже близко – ослабляем
    end

    priority_weight = 0.10
    has_turnover = providers_data.any? { |p| p['daily_turnover_min'].to_f > 0 || p['daily_turnover_max'].to_f > 0 }
    turnover_weight = has_turnover ? 0.10 : 0.0

    # Новые факторы – фиксированные небольшие веса
    amount_fit_weight = 0.05
    current_load_weight = 0.05

    {
      traffic: traffic_volume_weight,
      volume: traffic_volume_weight,
      conversion: conversion_weight,
      priority: priority_weight,
      turnover_min: turnover_weight,
      turnover_max: turnover_weight,
      amount_fit: amount_fit_weight,
      current_load: current_load_weight
    }
  end
end