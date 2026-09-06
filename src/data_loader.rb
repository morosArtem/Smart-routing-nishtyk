# src/data_loader.rb
require 'json'
require_relative 'config'
require_relative 'history_analyzer'

module DataLoader
  extend self

  def load
    providers_data = load_providers
    queue = load_queue
    history = load_history

    {
      providers_data: providers_data,
      queue: queue,
      history: history
    }
  end

  def load_providers
    unless File.exist?(Config::PROVIDERS_PATH)
      raise "❌ Файл провайдеров не найден: #{Config::PROVIDERS_PATH}"
    end
    data = JSON.parse(File.read(Config::PROVIDERS_PATH))
    data['providers']
  rescue JSON::ParserError => e
    raise "❌ Ошибка парсинга providers.json: #{e.message}"
  end

  def load_queue
    unless File.exist?(Config::QUEUE_PATH)
      raise "❌ Файл очереди не найден: #{Config::QUEUE_PATH}"
    end
    queue = JSON.parse(File.read(Config::QUEUE_PATH))
    if queue.empty?
      puts "⚠️  Очередь пуста, ничего не делаем"
      exit 0
    end
    queue
  rescue JSON::ParserError => e
    raise "❌ Ошибка парсинга queue: #{e.message}"
  end

  def load_history
    HistoryAnalyzer.analyze(Config::HISTORY_PATH)
  end
end