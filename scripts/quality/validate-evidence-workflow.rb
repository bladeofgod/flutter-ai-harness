#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

UPLOAD_ACTION = "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"
REQUIRED_JOBS = %w[check android-build ios-build].freeze

abort "Usage: validate-evidence-workflow.rb <ci.yml>" unless ARGV.length == 1

workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: false)
jobs = workflow.fetch("jobs")

REQUIRED_JOBS.each do |job_name|
  job = jobs.fetch(job_name)
  steps = job.fetch("steps")
  capture_steps = steps.select { |step| step.fetch("run", "").include?("capture-evidence.sh") }
  abort "#{job_name} does not capture a full redacted log" if capture_steps.empty?
  abort "#{job_name} does not pass --artifact" unless capture_steps.all? do |step|
    step.fetch("run").include?("--artifact")
  end

  uploads = steps.select { |step| step["uses"] == UPLOAD_ACTION }
  abort "#{job_name} must have exactly one pinned upload step" unless uploads.length == 1
  upload = uploads.first
  settings = upload.fetch("with")
  abort "#{job_name} upload must use if: always()" unless upload["if"] == "always()"
  abort "#{job_name} retention must be 14 days" unless settings["retention-days"] == 14
  abort "#{job_name} upload must fail when the log is missing" unless settings["if-no-files-found"] == "error"
  abort "#{job_name} upload must exclude hidden files" unless settings["include-hidden-files"].to_s == "false"
  name = settings.fetch("name")
  abort "#{job_name} artifact name lacks job/run attempt identity" unless
    name.include?("${{ github.job }}") && name.include?("${{ github.run_attempt }}")
  path = settings.fetch("path")
  abort "#{job_name} artifact path must be one explicit log" unless
    path == "${{ env.EVIDENCE_ARTIFACT }}"
  abort "#{job_name} upload must run after capture" unless
    steps.index(upload) > capture_steps.map { |step| steps.index(step) }.max
end
