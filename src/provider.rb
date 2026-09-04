# src/provider.rb
# Класс, представляющий платёжного провайдера с состоянием и методами для проверки и обновления.

class Provider
  attr_reader :id, :payment_system, :status, :traffic_percentage, :volume_share_pct,
              :limit_amount_min, :limit_amount_max, :daily_amount_limit,
              :in_progress_count_limit, :in_progress_amount_limit,
              :available_requisites, :banks, :exclude_banks,
              :conversion_24h, :provider_margin_pct, :merchant_margin_pct,
              :priority, :requests_per_minute_limit,
              :daily_turnover_min, :daily_turnover_max, :avg_latency_sec,
              :allow_negative_agreement

  attr_accessor :daily_approved_amount, :daily_approved_count,
                :in_progress_count, :in_progress_amount

  def initialize(attrs = {})
    attrs = attrs.transform_keys(&:to_s)

    @id = attrs['id']
    @payment_system = attrs['payment_system'] || attrs['id']
    @status = attrs['status'] || 'active'
    @traffic_percentage = attrs['traffic_percentage'].to_f
    @volume_share_pct = attrs['volume_share_pct'] ? attrs['volume_share_pct'].to_f : 0.0
    @limit_amount_min = attrs['limit_amount_min'] ? attrs['limit_amount_min'].to_f : 0.0
    @limit_amount_max = attrs['limit_amount_max'] ? attrs['limit_amount_max'].to_f : Float::INFINITY
    @daily_amount_limit = attrs['daily_amount_limit'] ? attrs['daily_amount_limit'].to_f : Float::INFINITY
    @daily_approved_amount = attrs['daily_approved_amount'].to_f
    @daily_approved_count = attrs['daily_approved_count'].to_i
    @in_progress_count_limit = attrs['in_progress_count_limit'] ? attrs['in_progress_count_limit'].to_i : Float::INFINITY
    @in_progress_count = attrs['in_progress_count'].to_i
    @in_progress_amount_limit = attrs['in_progress_amount_limit'] ? attrs['in_progress_amount_limit'].to_f : Float::INFINITY
    @in_progress_amount = attrs['in_progress_amount'].to_f
    @available_requisites = attrs['available_requisites'].to_i
    @banks = attrs['banks'] || []
    # Исправление: exclude_banks — булево значение
    @exclude_banks = !!attrs['exclude_banks']
    @conversion_24h = attrs['conversion_24h'].to_f
    @provider_margin_pct = attrs['provider_margin_pct'].to_f
    @merchant_margin_pct = attrs['merchant_margin_pct'].to_f
    @priority = attrs['priority'] ? attrs['priority'].to_i : 999
    @requests_per_minute_limit = attrs['requests_per_minute_limit'] ? attrs['requests_per_minute_limit'].to_i : Float::INFINITY
    @daily_turnover_min = attrs['daily_turnover_min'] ? attrs['daily_turnover_min'].to_f : 0.0
    @daily_turnover_max = attrs['daily_turnover_max'] ? attrs['daily_turnover_max'].to_f : Float::INFINITY
    @avg_latency_sec = attrs['avg_latency_sec'] ? attrs['avg_latency_sec'].to_i : 30

    @allow_negative_agreement =
      case attrs['allow_negative_agreement']
      when true, 'true', 1, '1' then true
      else false
      end

    @request_timestamps = []
  end

  def to_h
    {
      'id' => @id,
      'payment_system' => @payment_system,
      'status' => @status,
      'traffic_percentage' => @traffic_percentage,
      'volume_share_pct' => @volume_share_pct,
      'limit_amount_min' => @limit_amount_min,
      'limit_amount_max' => @limit_amount_max,
      'daily_amount_limit' => @daily_amount_limit,
      'daily_approved_amount' => @daily_approved_amount,
      'daily_approved_count' => @daily_approved_count,
      'in_progress_count_limit' => @in_progress_count_limit,
      'in_progress_count' => @in_progress_count,
      'in_progress_amount_limit' => @in_progress_amount_limit,
      'in_progress_amount' => @in_progress_amount,
      'available_requisites' => @available_requisites,
      'banks' => @banks,
      'exclude_banks' => @exclude_banks,
      'conversion_24h' => @conversion_24h,
      'provider_margin_pct' => @provider_margin_pct,
      'merchant_margin_pct' => @merchant_margin_pct,
      'priority' => @priority,
      'requests_per_minute_limit' => @requests_per_minute_limit,
      'daily_turnover_min' => @daily_turnover_min,
      'daily_turnover_max' => @daily_turnover_max,
      'avg_latency_sec' => @avg_latency_sec,
      'allow_negative_agreement' => @allow_negative_agreement
    }
  end

  # Начало обработки операции (увеличиваем счётчики in-progress)
  def start_operation(amount)
    @in_progress_count += 1
    @in_progress_amount += amount
    @request_timestamps << Time.now.to_i
  end

  # Завершение операции (уменьшаем in-progress и обновляем дневные метрики)
  def finish_operation(amount, approved:)
    @in_progress_count = [@in_progress_count - 1, 0].max
    @in_progress_amount = [@in_progress_amount - amount, 0.0].max

    if approved
      @daily_approved_amount += amount
      @daily_approved_count += 1
    end
  end

  # Сброс дневных метрик (для тестов)
  def reset_daily_metrics
    if @in_progress_count > 0 || @in_progress_amount > 0
      warn "Cannot reset daily metrics for #{@payment_system} – operations in progress"
      return
    end
    @daily_approved_amount = 0.0
    @daily_approved_count = 0
    @in_progress_count = 0
    @in_progress_amount = 0.0
    @request_timestamps.clear
  end

  # Проверка превышения лимита интенсивности (запросов в минуту)
  def rate_limit_exceeded?
    now = Time.now.to_i
    @request_timestamps.reject! { |t| now - t > 60 }
    @request_timestamps.size >= @requests_per_minute_limit
  end

  # Расчёт загрузки дневного лимита (в процентах)
  def daily_utilization_pct
    return 0 if @daily_amount_limit == Float::INFINITY
    (@daily_approved_amount / @daily_amount_limit * 100).round(2)
  end

  # Основной метод проверки hard-constraints (эквивалент filter.rb)
  def can_handle?(amount, bank: nil)
    return false unless @status == 'active'
    return false if amount < @limit_amount_min || amount > @limit_amount_max
    return false if @daily_approved_amount + amount > @daily_amount_limit
    return false if @in_progress_count >= @in_progress_count_limit
    return false if @in_progress_amount + amount > @in_progress_amount_limit
    return false if @available_requisites <= 0
    return false if rate_limit_exceeded?
    return false if !@allow_negative_agreement && @provider_margin_pct > @merchant_margin_pct

    # Проверка банковского фильтра
    if bank
      if @banks.any?
        if @exclude_banks
          # Если exclude_banks == true, то bank НЕ должен входить в список исключаемых
          return false if @banks.include?(bank)
        else
          # Иначе bank должен входить в список разрешённых
          return false unless @banks.include?(bank)
        end
      end
    end

    true
  end

  def to_s
    "Provider #{@payment_system} (status=#{@status}, daily_amount=#{@daily_approved_amount}/#{@daily_amount_limit}, daily_count=#{@daily_approved_count})"
  end
end