# src/main.rb

require 'json'
require_relative 'routing'
require_relative 'provider'
require_relative 'soft_filter'

# ---- Вот это главное изменение ----
# Строим пути относительно папки, где лежит main.rb
BASE_DIR = __dir__   # это путь к папке src/

PROVIDERS_PATH = File.join(BASE_DIR, '..', 'data', 'providers.json')
QUEUE_PATH = File.join(BASE_DIR, '..', 'data', 'operations_queue_10.json')
OUTPUT_PATH = File.join(BASE_DIR, '..', 'routing_decisions.json')
# ---------------------------------

def load_data
  providers_data = JSON.parse(File.read(PROVIDERS_PATH))
  queue = JSON.parse(File.read(QUEUE_PATH))
  [providers_data['providers'], queue]
end

if __FILE__ == $0
  providers_data, queue = load_data
  
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