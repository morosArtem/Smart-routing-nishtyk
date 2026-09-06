# src/router.rb
# Основной цикл обработки очереди, fallback и генерация attempts.
# Использует ProviderFilter для hard-constraints и SoftFilter для ранжирования.

require_relative 'provider'
require_relative 'soft_filter'

class Router
  LOG_FILE = 'router.log'

  def self.log(message)
    File.open(LOG_FILE, 'a') { |f| f.puts "#{Time.now}: #{message}" }
    puts message
  end

  def self.process_queue(providers_data, queue, weights = {})
    providers = providers_data.map { |p| p.is_a?(Provider) ? p : Provider.new(p) }
    decisions = []

    total_count = providers.sum { |p| p.daily_approved_count }
    total_amount = providers.sum { |p| p.daily_approved_amount }
    total_count = 1 if total_count == 0
    total_amount = 1.0 if total_amount == 0.0
    global_stats = {
      total_approved_count: total_count,
      total_approved_amount: total_amount
    }

    queue.each do |operation|
      log "Processing operation #{operation['operation_id']}"

      eligible, skip_reasons = filter_providers(providers, operation)

      if eligible.empty?
        fallback = providers.find { |p| p.payment_system == 'spacepayments' }
        if fallback
          eligible = [fallback]
          skip_reasons['spacepayments'] = ['fallback_used'] unless skip_reasons.key?('spacepayments')
          log "Fallback used for #{operation['operation_id']}"
        else
          log "ERROR: No eligible provider and no fallback for #{operation['operation_id']}"
          decisions << {
            'operation_id' => operation['operation_id'],
            'selected_provider' => nil,
            'attempts' => [],
            'simulated_result' => 'failed',
            'latency_sec' => 0
          }
          next
        end
      end

      # Получаем оценки для всех провайдеров, прошедших hard-фильтр
      scored = SoftFilter.score_providers(eligible, operation, weights, global_stats)
      selected = scored.first[:provider]

      # Симулируем результат и обновляем состояние
      simulated_result = simulate_result(selected)
      selected.start_operation(operation['amount'])
      selected.finish_operation(operation['amount'], approved: (simulated_result == 'approved'))

      global_stats[:total_approved_count] += 1
      global_stats[:total_approved_amount] += operation['amount'].to_f

      # Генерируем attempts с детальными причинами, используя scored
      attempts = build_attempts(providers, operation, selected, skip_reasons, scored)
      latency_sec = selected.avg_latency_sec || 30

      decision = {
        'operation_id' => operation['operation_id'],
        'selected_provider' => selected.payment_system,
        'attempts' => attempts,
        'simulated_result' => simulated_result,
        'latency_sec' => latency_sec
      }

      decisions << decision
      log "Selected #{selected.payment_system} for #{operation['operation_id']}"
    end

    decisions
  end

  # ----- Вспомогательные методы -----

  def self.filter_providers(providers, operation)
    eligible = []
    skip_reasons = {}
    amount = operation['amount']
    bank = operation['bank']

    providers.each do |provider|
      reasons = []
      ok = true

      # Проверка статуса
      if provider.status != 'active'
        ok = false
        reasons << "status_not_active: current status = #{provider.status}"
      end

      # Проверка диапазона суммы
      if amount < provider.limit_amount_min || amount > provider.limit_amount_max
        ok = false
        reasons << "amount_out_of_range: #{amount} not in [#{provider.limit_amount_min}, #{provider.limit_amount_max}]"
      end

      # Дневной лимит
      if provider.daily_approved_amount + amount > provider.daily_amount_limit
        ok = false
        reasons << "daily_limit_exceeded: #{provider.daily_approved_amount} + #{amount} > #{provider.daily_amount_limit}"
      end

      # Лимит in-progress по количеству
      if provider.in_progress_count >= provider.in_progress_count_limit
        ok = false
        reasons << "in_progress_count_exceeded: #{provider.in_progress_count} >= #{provider.in_progress_count_limit}"
      end

      # Лимит in-progress по сумме
      if provider.in_progress_amount + amount > provider.in_progress_amount_limit
        ok = false
        reasons << "in_progress_amount_exceeded: #{provider.in_progress_amount} + #{amount} > #{provider.in_progress_amount_limit}"
      end

      # Банковский фильтр
      if bank && provider.banks.any?
        if provider.exclude_banks
          if provider.banks.include?(bank)
            ok = false
            reasons << "bank_in_excluded_list: #{bank} excluded"
          end
        else
          unless provider.banks.include?(bank)
            ok = false
            reasons << "bank_not_in_list: #{bank} not in #{provider.banks}"
          end
        end
      end

      # Маржа
      if !provider.allow_negative_agreement && provider.provider_margin_pct > provider.merchant_margin_pct
        ok = false
        reasons << "margin_exceeds: #{provider.provider_margin_pct} > #{provider.merchant_margin_pct}"
      end

      # Реквизиты
      if provider.available_requisites <= 0
        ok = false
        reasons << "no_requisites: available = #{provider.available_requisites}"
      end

      # Интенсивность
      if provider.rate_limit_exceeded?
        ok = false
        reasons << "rate_limit_exceeded: requests per minute > #{provider.requests_per_minute_limit}"
      end

      # Отрицательные лимиты
      if provider.limit_amount_max < 0 || provider.limit_amount_min < 0 || provider.daily_amount_limit < 0
        ok = false
        reasons << "negative_limits: min=#{provider.limit_amount_min}, max=#{provider.limit_amount_max}, daily=#{provider.daily_amount_limit}"
      end

      if ok
        eligible << provider
      else
        skip_reasons[provider.payment_system] = reasons
      end
    end

    [eligible, skip_reasons]
  end

  def self.build_attempts(providers, operation, selected, skip_reasons, scored)
  attempts = []
  providers.each do |provider|
    ps = provider.payment_system
    if skip_reasons.key?(ps)
      # Провайдер исключён на этапе hard-фильтрации
      reasons = skip_reasons[ps]
      first_reason = reasons.first
      details = reasons.join('; ')
      attempts << {
        'provider' => ps,
        'decision' => 'skipped',
        'reason' => first_reason,
        'details' => details
      }
    elsif ps == selected.payment_system
      attempts << {
        'provider' => ps,
        'decision' => 'selected',
        'reason' => 'best_by_strategy'
      }
    else
      # Провайдер прошёл hard-фильтр, но не выбран soft-стратегией
      scored_entry = scored.find { |item| item[:provider].payment_system == ps }
      if scored_entry
        score = scored_entry[:score]
        selected_score = scored.first[:score]
        details_hash = scored_entry[:details]

        # Формируем объяснение, почему оценка низкая
        explanation_parts = []
        # Анализируем каждый фактор
        if details_hash[:traffic]
          dev = details_hash[:traffic][:deviation]
          if dev < 0
            explanation_parts << "недобор доли трафика (#{(dev * 100).round(1)}%)"
          end
        end
        if details_hash[:volume]
          dev = details_hash[:volume][:deviation]
          if dev < 0
            explanation_parts << "недобор доли объёма (#{(dev * 100).round(1)}%)"
          end
        end
        if details_hash[:conversion]
          conv = details_hash[:conversion]
          if conv < 0.7
            explanation_parts << "низкая конверсия (#{(conv * 100).round(1)}%)"
          end
        end
        if details_hash[:priority]
          # Чем больше priority, тем хуже – не добавляем, т.к. это уже учтено в оценке
        end
        if details_hash[:turnover_min]
          deficit = details_hash[:turnover_min][:deficit]
          if deficit > 0
            explanation_parts << "недобор минимального оборота (#{(deficit * 100).round(1)}%)"
          end
        end
        if details_hash[:turnover_max]
          excess = details_hash[:turnover_max][:excess]
          if excess > 0
            explanation_parts << "превышение максимального оборота (#{(excess * 100).round(1)}%)"
          end
        end
        if details_hash[:amount_fit]
          fit = details_hash[:amount_fit][:fit]
          if fit < 0.5
            explanation_parts << "сумма далека от центра диапазона (fit=#{fit.round(2)})"
          end
        end
        if details_hash[:current_load]
          penalty = details_hash[:current_load][:penalty]
          if penalty > 0.2
            explanation_parts << "высокая загрузка in-progress (штраф #{penalty.round(2)})"
          end
        end

        if explanation_parts.empty?
          explanation = "оценка #{score.round(6)} против #{selected_score.round(6)} у выбранного"
        else
          explanation = "оценка #{score.round(6)} (против #{selected_score.round(6)} у выбранного); причины: " + explanation_parts.join('; ')
        end

        attempts << {
          'provider' => ps,
          'decision' => 'skipped',
          'reason' => 'lower_score',
          'details' => explanation
        }
      else
        attempts << {
          'provider' => ps,
          'decision' => 'skipped',
          'reason' => 'unknown',
          'details' => "not in scored list"
        }
      end
    end
  end
  attempts
end

  def self.simulate_result(provider)
    conversion = provider.conversion_24h.to_f
    rand_num = rand
    if rand_num < conversion
      'approved'
    elsif rand_num < conversion + 0.05   # 5% шанс на expired
      'expired'
    else
      'rejected'
    end
  end
end