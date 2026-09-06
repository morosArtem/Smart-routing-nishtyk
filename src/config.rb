# src/config.rb
# Конфигурация путей и настроек

module Config
  BASE_DIR = __dir__
  PROJECT_ROOT = File.expand_path('..', BASE_DIR)

  DATA_DIR = File.join(PROJECT_ROOT, 'data')
  PROVIDERS_PATH = File.join(DATA_DIR, 'providers.json')
  QUEUE_PATH = File.join(DATA_DIR, 'operations_queue_10.json')
  HISTORY_PATH = File.join(DATA_DIR, 'operations_history.csv')

  OUTPUT_DIR = PROJECT_ROOT
  DECISIONS_PATH = File.join(OUTPUT_DIR, 'routing_decisions_test.json')
  REPORT_PATH = File.join(OUTPUT_DIR, 'routing_report_test.json')

  # Полный набор весов по умолчанию (используется, если история пуста)
  DEFAULT_WEIGHTS = {
    traffic: 0.20,
    volume: 0.20,
    conversion: 0.20,
    priority: 0.10,
    turnover_min: 0.10,
    turnover_max: 0.10,
    amount_fit: 0.05,
    current_load: 0.05
  }.freeze
end