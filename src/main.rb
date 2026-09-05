# src/main.rb
require 'json'
require_relative 'routing'
require_relative 'provider'
require_relative 'soft_filter'
require_relative 'history_analyzer'

BASE_DIR = __dir__
PROVIDERS_PATH = File.join(BASE_DIR, '..', 'data', 'providers.json')
QUEUE_PATH = File.join(BASE_DIR, '..', 'data', 'operations_queue_10.json')
HISTORY_PATH = File.join(BASE_DIR, '..', 'data', 'operations_history.csv')
OUTPUT_DECISIONS_PATH = File.join(BASE_DIR, '..', 'routing_decisions_test.json')
OUTPUT_REPORT_PATH = File.join(BASE_DIR, '..', 'routing_report_test.json')

def load_data
  providers_data = JSON.parse(File.read(PROVIDERS_PATH))['providers']
  queue = JSON.parse(File.read(QUEUE_PATH))
  [providers_data, queue]
end

def build_report(decisions, providers, history)
  # Распределение по выбранным провайдерам
  distribution = {}
  decisions.each do |dec|
    ps = dec['selected_provider']
    distribution[ps] ||= { 'count' => 0 }
    distribution[ps]['count'] += 1
  end
  total = decisions.size
  distribution.each do |ps, data|
    data['share_pct'] = (data['count'].to_f / total * 100).round(2)
    provider = providers.find { |p| p.payment_system == ps }
    data['target_pct'] = provider ? provider.traffic_percentage : 0
  end

  # Причины пропусков
  skip_reasons = {}
  decisions.each do |dec|
    dec['attempts'].each do |attempt|
      next if attempt['decision'] == 'selected'
      reason = attempt['reason']
      skip_reasons[reason] ||= 0
      skip_reasons[reason] += 1
    end
  end

  # Прогнозная загрузка лимитов
  projected_util = {}
  providers.each do |p|
    projected_util[p.payment_system] = {
      'used' => p.daily_approved_amount.round(2),
      'limit' => p.daily_amount_limit == Float::INFINITY ? nil : p.daily_amount_limit,
      'utilization_pct' => p.daily_amount_limit == Float::INFINITY ? nil : (p.daily_approved_amount / p.daily_amount_limit * 100).round(2)
    }
  end

  # Рекомендации
  recommendations = []
  history.each do |ps, hist|
    target = providers.find { |p| p.payment_system == ps }&.traffic_percentage || 0
    actual = hist[:count_share] * 100
    diff = (actual - target).abs
    if diff > 5
      if actual > target
        recommendations << "#{ps} получает #{actual.round(1)}% трафика при цели #{target}% — рекомендуется снизить traffic_percentage"
      else
        recommendations << "#{ps} получает #{actual.round(1)}% трафика при цели #{target}% — рекомендуется повысить traffic_percentage"
      end
    end

    if hist[:conversion] < 0.7
      recommendations << "#{ps} имеет низкую конверсию (#{(hist[:conversion]*100).round(1)}%) — рассмотрите снижение трафика или улучшение качества"
    end
  end

  providers.each do |p|
    if p.daily_amount_limit < Float::INFINITY && p.daily_approved_amount / p.daily_amount_limit > 0.8
      recommendations << "#{p.payment_system} близок к дневному лимиту (#{p.daily_approved_amount}/#{p.daily_amount_limit}) — снизить трафик или увеличить лимит"
    end
  end

  {
    'period' => Time.now.strftime('%Y-%m-%d'),
    'total_operations' => total,
    'distribution' => distribution,
    'skip_reasons' => skip_reasons,
    'projected_daily_utilization' => projected_util,
    'recommendations' => recommendations
  }
end

if __FILE__ == $0
  providers_data, queue = load_data

  history = HistoryAnalyzer.analyze(HISTORY_PATH)

  # Обновляем провайдеров данными из истории
  providers_data.each do |p|
    ps = p['payment_system']
    if history[ps]
      p['conversion_24h'] = history[ps][:conversion]
      p['avg_latency_sec'] = history[ps][:avg_latency].to_i
    end
  end

  providers = providers_data.map { |p| Provider.new(p) }

  weights = {
    traffic: 0.20,
    volume: 0.20,
    conversion: 0.20,
    priority: 0.15,
    turnover_min: 0.10,
    turnover_max: 0.05,
    utilization: 0.10
  }

  decisions = Router.process_queue(providers, queue, weights)

  File.write(OUTPUT_DECISIONS_PATH, JSON.pretty_generate(decisions))
  puts "✅ Решения сохранены в #{OUTPUT_DECISIONS_PATH}"

  report = build_report(decisions, providers, history)
  File.write(OUTPUT_REPORT_PATH, JSON.pretty_generate(report))
  puts "✅ Отчет сохранен в #{OUTPUT_REPORT_PATH}"
end
