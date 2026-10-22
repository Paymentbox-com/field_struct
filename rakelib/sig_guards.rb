# frozen_string_literal: true

# Ratchets that keep sig/ from getting *less* typed. Both work without Steep:
#
# * An +untyped+ ceiling. The committed count of non-comment +untyped+ tokens
#   under sig/ may only go down. Going over fails (a change added +untyped+);
#   going under also fails, until the ceiling is lowered to the new count, so
#   the slack can never be spent later.
# * A sord warning allowlist. Every +[OMIT]+ (no YARD type, sord wrote
#   +untyped+) and +[DUCK]+ (duck type, sord wrote +untyped+ or an interface)
#   warning must be listed. An unlisted warning fails (new untyped surface); a
#   listed one sord no longer emits also fails (remove it), so the list only
#   shrinks.
#
# Entries carry no file:line, so moving code doesn't churn the allowlist.
#
# Pure functions here; the rake tasks in the Rakefile wire them to files.
module SigGuards
  # The committed ceiling: one integer.
  UNTYPED_CEILING_FILE = File.expand_path('sig_guards/untyped_ceiling.txt', __dir__)
  # The committed sord allowlist: one warning per line, +#+ comments allowed.
  SORD_ALLOWLIST_FILE = File.expand_path('sig_guards/sord_allowlist.txt', __dir__)

  UNTYPED_TOKEN = /\buntyped\b/
  # [OMIT ] (FieldStruct::Field#initialize) lib/field_struct/field.rb:59: no YARD type given for "x", using untyped
  SORD_WARNING = /^\[(?<kind>OMIT|DUCK)\s*\] \((?<object>[^)]+)\) \S+:\d+: (?<message>.+)$/

  module_function

  # @param paths [Array<String>] .rbs files
  # @return [Integer] +untyped+ tokens outside comments
  def count_untyped(paths)
    paths.sum do |path|
      File.foreach(path).sum { |line| line.sub(/#.*/, '').scan(UNTYPED_TOKEN).size }
    end
  end

  # @param count [Integer] the measured count
  # @param ceiling [Integer] the committed ceiling
  # @return [String, nil] why the check fails, or nil when count == ceiling
  def untyped_failure(count:, ceiling:)
    if count > ceiling
      "sig/ has #{count} `untyped` (ceiling #{ceiling}): #{count - ceiling} new. " \
        'Type them in YARD (or a hand-written sig) instead of adding untyped.'
    elsif count < ceiling
      "sig/ has #{count} `untyped`, below the ceiling of #{ceiling}. " \
        "Lower the ceiling to #{count} in #{relative(UNTYPED_CEILING_FILE)} so it can't creep back up."
    end
  end

  # @param output [String] sord's combined stdout/stderr
  # @return [Array<String>] sorted, unique allowlist keys for each OMIT/DUCK warning
  def sord_warnings(output)
    plain = output.gsub(/\e\[[0-9;]*m/, '')
    plain.lines.filter_map do |line|
      m = SORD_WARNING.match(line.strip) or next
      "#{m[:kind]} (#{m[:object]}) #{m[:message]}"
    end.uniq.sort
  end

  # @param text [String] allowlist file contents
  # @return [Array<String>] entries, without comments and blank lines
  def parse_allowlist(text)
    text.lines.map(&:strip).reject { |line| line.empty? || line.start_with?('#') }
  end

  # @param warnings [Array<String>] keys from {sord_warnings}
  # @param allowlist [Array<String>] entries from {parse_allowlist}
  # @return [String, nil] why the check fails, or nil when they match exactly
  def allowlist_failure(warnings:, allowlist:)
    unlisted = warnings - allowlist
    stale = allowlist - warnings
    return if unlisted.empty? && stale.empty?

    file = relative(SORD_ALLOWLIST_FILE)
    parts = []
    unless unlisted.empty?
      parts << "#{unlisted.size} new sord warning(s) — each is a spot where sord wrote untyped " \
               "(or a duck interface). Add a YARD type; only if that's impossible, add the line to #{file}:"
      parts.concat(unlisted.map { |entry| "  #{entry}" })
    end
    unless stale.empty?
      parts << "#{stale.size} allowlisted warning(s) sord no longer emits — remove them from #{file}:"
      parts.concat(stale.map { |entry| "  #{entry}" })
    end
    parts.join("\n")
  end

  def relative(path)
    path.delete_prefix("#{File.expand_path("..", __dir__)}/")
  end
end
