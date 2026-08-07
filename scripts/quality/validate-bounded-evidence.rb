#!/usr/bin/env ruby
# frozen_string_literal: true

MAX_FILE_BYTES = 524_288
MAX_FILE_LINES = 4_800
MAX_RECORD_BYTES = 65_536
MAX_RECORD_LINES = 600

abort "Usage: validate-bounded-evidence.rb <evidence.log>" unless ARGV.length == 1

path = ARGV.fetch(0)
content = File.binread(path).force_encoding(Encoding::UTF_8).scrub
abort "bounded evidence exceeds the file byte limit" if content.bytesize > MAX_FILE_BYTES
abort "bounded evidence exceeds the file line limit" if content.lines.count > MAX_FILE_LINES

records = content.split(/(?=^Evidence format: bounded-v1$)/)
records.reject! { |record| record.strip.empty? }
abort "bounded evidence has no records" if records.empty?

records.each_with_index do |record, index|
  label = "record #{index + 1}"
  abort "#{label} has an unknown evidence format" unless record.start_with?("Evidence format: bounded-v1\n")
  abort "#{label} exceeds the byte limit" if record.bytesize > MAX_RECORD_BYTES
  abort "#{label} exceeds the line limit" if record.lines.count > MAX_RECORD_LINES
  %w[Command Tool\ Versions Result Output\ Summary].each do |heading|
    abort "#{label} is missing #{heading}" unless record.include?("## #{heading.tr('\\', '')}\n")
  end

  exit_code = record[/^Exit code: (-?\d+)$/, 1]
  digest = record[/^Output SHA-256: ([0-9a-f]{64})$/, 1]
  original_bytes = record[/^Original output bytes: (\d+)$/, 1]
  original_lines = record[/^Original output lines: (\d+)$/, 1]
  summary_bytes = record[/^Summary output bytes: (\d+)$/, 1]
  summary_lines = record[/^Summary output lines: (\d+)$/, 1]
  truncated = record[/^Truncated: (yes|no)$/, 1]
  selection = record[/^Selection: (success-stable-lines-v1|failure-root-context-v1)$/, 1]
  abort "#{label} has invalid result metadata" unless exit_code && digest && original_bytes &&
    original_lines && summary_bytes && summary_lines && truncated && selection

  output = record[/^## Output Summary\n\n```text\n(.*?)\n```\s*\z/m, 1]
  abort "#{label} has an invalid summary block" unless output
  abort "#{label} summary byte count drifted" unless output.bytesize == Integer(summary_bytes, 10)
  abort "#{label} summary line count drifted" unless output.lines.count == Integer(summary_lines, 10)
  if truncated == "yes" && !output.include?("use the redacted CI artifact for full output")
    abort "#{label} is missing the explicit truncation marker"
  end
end
