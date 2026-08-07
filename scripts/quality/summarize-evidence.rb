#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"

MAX_SUMMARY_BYTES = 49_152
MAX_SUMMARY_LINES = 400
SMALL_OUTPUT_LINES = 120
SUCCESS_PATTERN = /(?:all tests passed|build successful|build succeeded|test succeeded|checks? passed|passed\b|成功|通过)/i
FAILURE_PATTERN = /(?:\berror\b|\bfail(?:ed|ure)?\b|exception|fatal|abort|could not|unable to)/i

abort "Usage: summarize-evidence.rb <sanitized-output> <exit-code>" unless ARGV.length == 2

path = ARGV.fetch(0)
status = Integer(ARGV.fetch(1), 10)
raw = File.binread(path)
text = raw.force_encoding(Encoding::UTF_8).scrub
lines = text.lines(chomp: true)

selected_indexes = if lines.length <= SMALL_OUTPUT_LINES
                     (0...lines.length).to_a
                   elsif status.zero?
                     stable = lines.each_index.select { |index| SUCCESS_PATTERN.match?(lines[index]) }
                     ((0...[20, lines.length].min).to_a +
                       stable.flat_map { |index| ((index - 1)..(index + 1)).to_a } +
                       (([lines.length - 30, 0].max)...lines.length).to_a)
                   else
                     root = lines.find_index { |line| FAILURE_PATTERN.match?(line) }
                     root ||= 0
                     (([root - 20, 0].max)..([root + 60, lines.length - 1].min)).to_a +
                       (([lines.length - 20, 0].max)...lines.length).to_a
                   end

selected_indexes = selected_indexes.select { |index| index.between?(0, lines.length - 1) }.uniq.sort
selected = selected_indexes.map { |index| lines[index] }
selection_truncated = selected_indexes.length != lines.length

if selected.length > MAX_SUMMARY_LINES
  selected = selected.first(MAX_SUMMARY_LINES - 1)
  selected << "...[summary line limit reached; use the redacted CI artifact for full output]..."
  selection_truncated = true
end

marker = "...[summary byte limit reached; use the redacted CI artifact for full output]..."
while selected.join("\n").bytesize > MAX_SUMMARY_BYTES && selected.length > 1
  selected.delete_at(selected.length / 2)
  selection_truncated = true
end
if selected.join("\n").bytesize > MAX_SUMMARY_BYTES
  budget = MAX_SUMMARY_BYTES - marker.bytesize - 1
  selected = [selected.first.byteslice(0, [budget, 0].max).to_s.force_encoding(Encoding::UTF_8).scrub, marker]
  selection_truncated = true
elsif selection_truncated && !selected.include?(marker)
  selected.insert(selected.length / 2, marker)
end

summary = selected.empty? ? "<no output>" : selected.join("\n")
puts "Output SHA-256: #{Digest::SHA256.hexdigest(raw)}"
puts "Original output bytes: #{raw.bytesize}"
puts "Original output lines: #{lines.length}"
puts "Summary output bytes: #{summary.bytesize}"
puts "Summary output lines: #{summary.lines.count}"
puts "Truncated: #{selection_truncated ? 'yes' : 'no'}"
puts "Selection: #{status.zero? ? 'success-stable-lines-v1' : 'failure-root-context-v1'}"
puts
puts "## Output Summary"
puts
puts "```text"
puts summary
puts "```"
