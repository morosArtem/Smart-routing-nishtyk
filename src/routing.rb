# src/filter.rb
# Класс для фильтрации провайдеров по hard-constraints.
# Принимает массив провайдеров (в формате providers.json) и параметры операции.
# Возвращает [массив допустимых провайдеров, хэш причин исключений].

class ProviderFilter
  def self.filter(providers, operation)
    eligible = []
    skip_reasons = {}

    providers.each do |provider|
      reasons = []
      ok = true

      unless check_status(provider)
        ok = false
        reasons << 'status_not_active'
      end

      unless check_amount_limits(provider, operation['amount'])
        ok = false
        reasons << 'amount_out_of_range'
      end

      unless check_daily_limit(provider, operation['amount'])
        ok = false
        reasons << 'daily_limit_exceeded'
      end

      unless check_in_progress_count(provider)
        ok = false
        reasons << 'in_progress_count_exceeded'
      end

      unless check_in_progress_amount(provider, operation['amount'])
        ok = false
        reasons << 'in_progress_amount_exceeded'
      end

      unless check_bank(provider, operation['bank'])
        ok = false
        reasons << 'bank_not_in_list'
      end

      unless check_margin(provider)
        ok = false
        reasons << 'margin_exceeds'
      end

      unless check_requisites(provider)
        ok = false
        reasons << 'no_requisites'
      end

      if ok
        eligible << provider
      else
        skip_reasons[provider['payment_system']] = reasons
      end
    end

    [eligible, skip_reasons]
  end

  # ----- Проверки (каждая – отдельный метод) -----

  def self.check_status(provider)
    provider['status'] == 'active'
  end

  def self.check_amount_limits(provider, amount)
    min = provider['limit_amount_min']
    max = provider['limit_amount_max']
    return true if min.nil? && max.nil?
    return false if min && amount < min
    return false if max && amount > max
    true
  end

  def self.check_daily_limit(provider, amount)
    limit = provider['daily_amount_limit']
    used = provider['daily_approved_amount'].to_f
    return true if limit.nil?
    (used + amount) <= limit
  end

  def self.check_in_progress_count(provider)
    limit = provider['in_progress_count_limit']
    current = provider['in_progress_count'].to_i
    return true if limit.nil?
    (current + 1) <= limit
  end

  def self.check_in_progress_amount(provider, amount)
    limit = provider['in_progress_amount_limit']
    current = provider['in_progress_amount'].to_f
    return true if limit.nil?
    (current + amount) <= limit
  end

  def self.check_bank(provider, bank)
    banks = provider['banks']
    return true if banks.nil? || banks.empty?
    if provider['exclude_banks'] == true
      !banks.include?(bank)
    else
      banks.include?(bank)
    end
  end

  def self.check_margin(provider)
    return true if provider['allow_negative_agreement'] == true
    provider['provider_margin_pct'].to_f <= provider['merchant_margin_pct'].to_f
  end

  def self.check_requisites(provider)
    provider['available_requisites'].to_i > 0
  end
end
