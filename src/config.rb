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

  # Настройки по умолчанию для весов (если история пуста)
  DEFAULT_WEIGHTS = {
    traffic: 0.25,
    volume: 0.25,
    conversion: 0.20,
    priority: 0.10,
    turnover_min: 0.10,
    turnover_max: 0.10
  }.freeze
end