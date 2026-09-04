# src/main.rb
# Точка входа: загружает данные, запускает роутинг, сохраняет результат.

require 'json'
require_relative 'router'
require_relative 'provider'

# Пути к файлам (можно передать аргументами)
PROVIDERS_PATH = 'data/providers.json'
QUEUE_PATH = 'data/operations_queue_10.json'
OUTPUT_PATH = 'routing_decisions.json'

# Загрузка данных
def load_data
  providers_data = JSON.parse(File.read(PROVIDERS_PATH))
  queue = JSON.parse(File.read(QUEUE_PATH))
  [providers_data['providers'], queue]
end

# Точка входа
if __FILE__ == $0
  providers_data, queue = load_data
  
  # Можно задать свои веса для стратегии
  weights = {
    traffic: 0.20,
    volume: 0.20,
    conversion: 0.20,
    priority: 0.15,
    turnover_min: 0.10,
    turnover_max: 0.05,
    utilization: 0.10
  }
  
  decisions = Router.process_queue(providers_data, queue, weights)
  
  File.write(OUTPUT_PATH, JSON.pretty_generate(decisions))
  puts "✅ Решения сохранены в #{OUTPUT_PATH}"
  puts "📊 Обработано операций: #{decisions.size}"
end