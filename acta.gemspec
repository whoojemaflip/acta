# frozen_string_literal: true

require_relative "lib/acta/version"

Gem::Specification.new do |spec|
  spec.name = "acta"
  spec.version = Acta::VERSION
  spec.authors = [ "Tom Gladhill" ]
  spec.email = [ "tom@gladhill.ca" ]

  spec.summary = "Lightweight event-driven and event-sourced primitives for Rails."
  spec.description = <<~DESC.strip
    Acta ships a small, opinionated set of primitives for event-driven and
    event-sourced Rails applications: events, handlers, projections, reactors,
    and commands. Projections run synchronously inside the emit transaction;
    reactors fan out via ActiveJob. ActiveModel-backed payloads with support
    for nested models and ActiveRecord piggyback. SQLite and Postgres adapters.
  DESC
  spec.homepage = "https://github.com/whoojemaflip/acta"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.require_paths = [ "lib" ]

  spec.add_dependency "activejob", ">= 7.2"
  spec.add_dependency "activemodel", ">= 7.2"
  spec.add_dependency "activerecord", ">= 7.2"
  spec.add_dependency "activesupport", ">= 7.2"
end
