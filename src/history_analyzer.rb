require 'csv'

class HistoryAnalyzer
  def self.analyze(file_path)
    return {} unless File.exist?(file_path)

    data = CSV.read(file_path, headers: true)
    groups = data.group_by { |row| row['payment_system'] }
    result = {}
    total_ops = data.size
    total_amount = data.sum { |r| r['amount'].to_f }

    groups.each do |ps, rows|
      total = rows.size
      approved = rows.count { |r| r['status'] == 'approved' }
      conversion = total > 0 ? approved.to_f / total : 0.5
      latencies = rows.map { |r| r['latency_sec'].to_f }.compact
      avg_latency = latencies.empty? ? 30 : latencies.sum / latencies.size
      count_share = total.to_f / total_ops
      amount_sum = rows.sum { |r| r['amount'].to_f }
      volume_share = total_amount > 0 ? amount_sum / total_amount : 0

      result[ps] = {
        conversion: conversion,
        avg_latency: avg_latency,
        count_share: count_share,
        volume_share: volume_share,
        total_operations: total,
        total_amount: amount_sum
      }
    end
    result
  end
end