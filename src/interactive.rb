# src/interactive.rb
# Модуль для интерактивного взаимодействия с пользователем (выбор режима, ввод весов)

module Interactive
  extend self

  def prompt_yes_no(question)
    loop do
      print "#{question} (y/n): "
      answer = gets.chomp.downcase
      return true if answer == 'y'
      return false if answer == 'n'
      puts "Пожалуйста, введите 'y' или 'n'."
    end
  end

  def prompt_float(name, default)
    loop do
      print "Введите вес для #{name} (по умолчанию #{default}): "
      input = gets.chomp
      return default if input.empty?
      begin
        value = Float(input)
        return value if value >= 0
        puts "Вес должен быть неотрицательным числом."
      rescue ArgumentError
        puts "Некорректный ввод. Введите число."
      end
    end
  end

  # Возвращает либо :auto, либо хэш с весами
  def get_weights(default_weights)
    puts "\n=== Настройка стратегии роутинга ==="
    auto_mode = prompt_yes_no("Использовать автоматические веса (на основе истории)")

    if auto_mode
      :auto
    else
      puts "\nВведите свои веса для каждого фактора (нажмите Enter, чтобы оставить значение по умолчанию):"
      weights = {}
      default_weights.each do |key, default|
        weights[key] = prompt_float(key.to_s, default)
      end
      weights
    end
  end
end