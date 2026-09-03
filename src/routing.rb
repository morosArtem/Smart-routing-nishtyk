# src/router.rb
# Основной цикл обработки очереди, fallback и генерация attempts.
# Использует ProviderFilter для hard-constraints.

require_relative 'filter'   # ваш класс ProviderFilter

class Router
  # Основной метод: обрабатывает все операции и возвращает массив решений
  # Параметры:
  #   providers - массив хэшей с данными провайдеров (уже загружен)
  #   queue     - массив хэшей с операциями (уже загружен)
  # Возвращает: массив решений в формате sample_routing_decisions.json
  def self.process_queue(providers, queue)
    decisions = []

    queue.each do |operation|
      # Шаг 1: фильтрация (hard-constraints) – используем ваш класс
      eligible, skip_reasons = ProviderFilter.filter(providers, operation)

      # Шаг 2: если eligible пуст, используем fallback (spacepayments)
      if eligible.empty?
        # Ищем провайдера spacepayments
        fallback = providers.find { |p| p['payment_system'] == 'spacepayments' }
        if fallback
          # Принудительно добавляем fallback как единственного eligible
          eligible = [fallback]
          # Примечание: skip_reasons уже содержит причины для остальных провайдеров
        else
          # Если даже fallback нет – пропускаем операцию (или выбрасываем ошибку)
          puts "WARNING: No eligible provider and no fallback for operation #{operation['operation_id']}"
          next
        end
      end

      # Шаг 3: выбор провайдера по простой стратегии – минимальный priority
      # (можно заменить на более сложную, но это уже задача напарника)
      selected = select_provider(eligible)

      # Шаг 4: обновление состояния выбранного провайдера (для учёта лимитов в следующих операциях)
      update_provider_state(selected, operation['amount'])

      # Шаг 5: генерация attempts для всех провайдеров
      attempts = build_attempts(providers, operation, selected, skip_reasons)

      # Шаг 6: симуляция результата на основе conversion_24h
      simulated_result = simulate_result(selected)
      latency_sec = selected['avg_latency_sec'] || 30   # дефолт, если нет значения

      # Формируем решение для этой операции
      decision = {
        'operation_id' => operation['operation_id'],
        'selected_provider' => selected['payment_system'],
        'attempts' => attempts,
        'simulated_result' => simulated_result,
        'latency_sec' => latency_sec
      }

      decisions << decision
    end

    decisions
  end

  # ----- Вспомогательные методы (только то, что нужно для цикла) -----

  # Простая стратегия выбора: провайдер с наименьшим priority (чем меньше число, тем выше приоритет)
  # Если priority не задан, считаем его бесконечностью.
  def self.select_provider(eligible)
    eligible.min_by { |p| p['priority'] || Float::INFINITY }
  end

  # Обновление состояния провайдера после выбора (увеличиваем счётчики)
  def self.update_provider_state(provider, amount)
    provider['daily_approved_amount'] = provider['daily_approved_amount'].to_f + amount
    provider['in_progress_count'] = provider['in_progress_count'].to_i + 1
    provider['in_progress_amount'] = provider['in_progress_amount'].to_f + amount
  end

  # Генерация массива attempts для всех провайдеров
  def self.build_attempts(providers, operation, selected, skip_reasons)
    attempts = []
    providers.each do |provider|
      ps = provider['payment_system']
      if skip_reasons.key?(ps)
        # Провайдер был исключён на этапе фильтрации
        reasons = skip_reasons[ps]
        attempts << {
          'provider' => ps,
          'decision' => 'skipped',
          'reason' => reasons.first,          # берём первую причину как основную
          'details' => reasons.join(', ')     # все причины для подробности
        }
      elsif ps == selected['payment_system']
        # Это выбранный провайдер
        attempts << {
          'provider' => ps,
          'decision' => 'selected',
          'reason' => 'best_by_strategy'
        }
      else
        # Провайдер прошёл фильтр, но не был выбран (например, более низкий приоритет)
        attempts << {
          'provider' => ps,
          'decision' => 'skipped',
          'reason' => 'lower_priority',
          'details' => "priority #{provider['priority']} vs selected #{selected['priority']}"
        }
      end
    end
    attempts
  end

  # Симуляция результата на основе conversion_24h
  def self.simulate_result(provider)
    conversion = provider['conversion_24h'].to_f
    rand < conversion ? 'approved' : 'rejected'
  end
end