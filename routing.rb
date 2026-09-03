require 'json'

# Основной класс фильтрации
class ProviderFilter
  # На вход: массив провайдеров и хэш операции (amount, bank)
  # На выход: [массив подходящих провайдеров, хэш причин исключений]
  def self.filter(providers, operation)
    eligible = []
    skip_reasons = {# src/filter.rb
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

      ok = false unless check_status(provider)         && (reasons << 'status_not_active')
      ok = false unless check_amount_limits(provider, operation['amount']) && (reasons << 'amount_out_of_range')
      ok = false unless check_daily_limit(provider, operation['amount'])   && (reasons << 'daily_limit_exceeded')
      ok = false unless check_in_progress_count(provider)                  && (reasons << 'in_progress_count_exceeded')
      ok = false unless check_in_progress_amount(provider, operation['amount']) && (reasons << 'in_progress_amount_exceeded')
      ok = false unless check_bank(provider, operation['bank'])            && (reasons << 'bank_not_in_list')
      ok = false unless check_margin(provider)                             && (reasons << 'margin_exceeds')
      ok = false unless check_requisites(provider)                         && (reasons << 'no_requisites')

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