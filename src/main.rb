# src/main.rb
require 'json'
require_relative 'config'
require_relative 'data_loader'
require_relative 'weight_calculator'
require_relative 'report_builder'
require_relative 'routing'
require_relative 'provider'

# Загрузка данных
data = DataLoader.load

# Обновление провайдеров данными из истории (если есть)
unless data[:history].empty?
  data[:providers_data].each do |p|
    ps = p['payment_system']
    hist = data[:history][ps]
    next unless hist
    p['conversion_24h'] = hist[:conversion]
    p['avg_latency_sec'] = hist[:avg_latency].to_i
    p['volume_share_pct'] = hist[:volume_share] * 100 if hist[:volume_share]
  end
end

# Вычисление динамических весов
weights = WeightCalculator.compute(data[:history], data[:providers_data])
puts "✅ Динамические веса: #{weights}"

# Создание объектов Provider
providers = data[:providers_data].map { |p| Provider.new(p) }

# Запуск роутера
decisions = Router.process_queue(providers, data[:queue], weights)

# Сохранение решений
File.write(Config::DECISIONS_PATH, JSON.pretty_generate(decisions))
puts "✅ Решения сохранены в #{Config::DECISIONS_PATH}"

# Построение и сохранение отчёта
report = ReportBuilder.build(decisions, providers, data[:history])
File.write(Config::REPORT_PATH, JSON.pretty_generate(report))
puts "✅ Отчет сохранен в #{Config::REPORT_PATH}"