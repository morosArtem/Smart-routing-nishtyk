# src/router.rb
# Основной цикл обработки очереди, fallback и генерация attempts.
# Использует ProviderFilter для hard-constraints и SoftFilter для ранжирования.

require_relative 'filter'
require_relative 'provider'
require_relative 'soft_filter'

class Router
  # Основной метод: обрабатывает все операции и возвращает массив решений
  def self.process_queue(providers_data, queue, weights = {})
    # Преобразуем хэши в объекты Provider
    providers = providers_data.map { |p| p.is_a?(Provider) ? p : Provider.new(p) }
    decisions = []

    # Глобальная статистика для soft-стратегий
    global_stats = {
      total_approved_count: providers.sum { |p| p.daily_approved_count },
      total_approved_amount: providers.sum { |p| p.daily_approved_amount }
    }

    queue.each do |operation|
      # Шаг 1: фильтрация (hard-constraints) – используем метод can_handle? из класса Provider
      eligible, skip_reasons = filter_providers(providers, operation)

      # Шаг 2: если eligible пуст, используем fallback (spacepayments)
      if eligible.empty?
        fallback = providers.find { |p| p.payment_system == 'spacepayments' }
        if fallback
          eligible = [fallback]
          # Добавляем причину, что использован fallback
          skip_reasons['spacepayments'] = [] unless skip_reasons.key?('spacepayments')
        else
          puts "WARNING: No eligible provider and no fallback for operation #{operation['operation_id']}"
          next
        end
      end

      # Шаг 3: выбор провайдера по soft-стратегии (используем SoftFilter)
      selected = SoftFilter.best_provider(eligible, operation, weights, global_stats)
      
      # Если SoftFilter вернул nil (маловероятно, но на всякий случай)
      if selected.nil?
        selected = eligible.first
      end

      # Шаг 4: обновление состояния выбранного провайдера (используем методы класса Provider)
      update_provider_state(selected, operation['amount'])

      # Обновляем глобальную статистику
      global_stats[:total_approved_count] += 1
      global_stats[:total_approved_amount] += operation['amount'].to_f

      # Шаг 5: генерация attempts для всех провайдеров
      attempts = build_attempts(providers, operation, selected, skip_reasons)

      # Шаг 6: симуляция результата на основе conversion_24h
      simulated_result = simulate_result(selected)
      latency_sec = selected.avg_latency_sec || 30

      # Формируем решение для этой операции
      decision = {
        'operation_id' => operation['operation_id'],
        'selected_provider' => selected.payment_system,
        'attempts' => attempts,
        'simulated_result' => simulated_result,
        'latency_sec' => latency_sec
      }

      decisions << decision
    end

    decisions
  end

  # ----- Вспомогательные методы -----

  # Фильтрация провайдеров (hard-constraints) через метод can_handle?
  def self.filter_providers(providers, operation)
    eligible = []
    skip_reasons = {}

    providers.each do |provider|
      if provider.can_handle?(operation['amount'], bank: operation['bank'])
        eligible << provider
      else
        # Собираем причины отказа
        reasons = []
        reasons << 'status_not_active' if provider.status != 'active'
        reasons << 'amount_out_of_range' if operation['amount'] < provider.limit_amount_min || operation['amount'] > provider.limit_amount_max
        reasons << 'daily_limit_exceeded' if provider.daily_approved_amount + operation['amount'] > provider.daily_amount_limit
        reasons << 'in_progress_count_exceeded' if provider.in_progress_count >= provider.in_progress_count_limit
        reasons << 'in_progress_amount_exceeded' if provider.in_progress_amount + operation['amount'] > provider.in_progress_amount_limit
        reasons << 'bank_not_in_list' if !provider.banks.empty? && !provider.banks.include?(operation['bank'])
        reasons << 'margin_exceeds' if !provider.allow_negative_agreement && provider.provider_margin_pct > provider.merchant_margin_pct
        reasons << 'no_requisites' if provider.available_requisites <= 0
        
        # Если причина не определена, ставим общую
        reasons << 'unknown' if reasons.empty?
        
        skip_reasons[provider.payment_system] = reasons
      end
    end

    [eligible, skip_reasons]
  end

  # Обновление состояния провайдера через методы класса Provider
  def self.update_provider_state(provider, amount)
    provider.start_operation(amount)
    # Симулируем успешное завершение (в реальности здесь был бы ответ от провайдера)
    provider.finish_operation(amount, approved: true)
  end

  # Генерация массива attempts для всех провайдеров
  def self.build_attempts(providers, operation, selected, skip_reasons)
    attempts = []
    providers.each do |provider|
      ps = provider.payment_system
      if skip_reasons.key?(ps)
        reasons = skip_reasons[ps]
        attempts << {
          'provider' => ps,
          'decision' => 'skipped',
          'reason' => reasons.first,
          'details' => reasons.join(', ')
        }
      elsif ps == selected.payment_system
        attempts << {
          'provider' => ps,
          'decision' => 'selected',
          'reason' => 'best_by_strategy'
        }
      else
        attempts << {
          'provider' => ps,
          'decision' => 'skipped',
          'reason' => 'lower_priority',
          'details' => "not selected by soft strategy"
        }
      end
    end
    attempts
  end

  # Симуляция результата на основе conversion_24h
  def self.simulate_result(provider)
    conversion = provider.conversion_24h.to_f
    rand < conversion ? 'approved' : 'rejected'
  end
end