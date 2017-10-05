# frozen_string_literal: true

require "bundler_definition_version_patch"
require "bundler_git_source_patch"

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler
        class ForceUpdater
          def initialize(dependency:, dependency_files:, github_access_token:,
                         target_version:)
            @dependency = dependency
            @dependency_files = dependency_files
            @github_access_token = github_access_token
            @target_version = target_version
          end

          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/MethodLength
          # rubocop:disable Metrics/BlockLength
          def force_update
            in_a_temporary_bundler_context do
              unlocked_gems = [dependency.name]

              begin
                definition = ::Bundler::Definition.build(
                  "Gemfile",
                  lockfile&.name,
                  gems: unlocked_gems
                )

                # Unlock the requirement in the Gemfile / gemspec
                unlocked_gems.each do |gem_name|
                  dep     = definition.dependencies.
                            find { |d| d.name == gem_name }
                  version = definition.locked_gems.specs.
                            find { |d| d.name == gem_name }.version

                  dep&.instance_variable_set(
                    :@requirement,
                    Gem::Requirement.create(">= #{version}")
                  )
                end

                target_dep = definition.dependencies.
                             find { |d| d.name == dependency.name }
                target_dep.instance_variable_set(
                  :@requirement,
                  Gem::Requirement.create("= #{target_version}")
                )

                definition.resolve_remotely!
                dep = definition.resolve.find { |d| d.name == dependency.name }
                { version: dep.version, unlocked_gems: unlocked_gems }
              rescue ::Bundler::VersionConflict => error
                # TODO: Not sure this won't unlock way too many things...
                # TODO: Some way of determining which of the several gems we
                #       could be doing a multi-update for to do it for. Could
                #       ignore this problem if all multi-updates generated
                #       identical PRs (i.e., if unlocking was perfect).
                to_unlock = error.cause.conflicts.values.flat_map do |conflict|
                  conflict.requirement_trees.map { |r| r.first.name }
                end
                raise unless (to_unlock - unlocked_gems).any?
                unlocked_gems |= to_unlock
                retry
              end
            end
          rescue SharedHelpers::ChildProcessFailed => error
            msg = error.error_class + " with message: " + error.error_message
            raise Dependabot::DependencyFileNotResolvable, msg
          end
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/MethodLength
          # rubocop:enable Metrics/BlockLength

          private

          attr_reader :dependency, :dependency_files, :github_access_token,
                      :target_version

          #########################
          # Bundler context setup #
          #########################

          def in_a_temporary_bundler_context
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                # Remove installed gems from the default Rubygems index
                ::Gem::Specification.all = []

                # Set auth details for GitHub
                ::Bundler.settings.set_command_option(
                  "github.com",
                  "x-access-token:#{github_access_token}"
                )

                yield
              end
            end
          end

          def gemfile
            dependency_files.find { |f| f.name == "Gemfile" }
          end

          def lockfile
            dependency_files.find { |f| f.name == "Gemfile.lock" }
          end

          def write_temporary_dependency_files
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, file.content)
            end
          end
        end
      end
    end
  end
end
