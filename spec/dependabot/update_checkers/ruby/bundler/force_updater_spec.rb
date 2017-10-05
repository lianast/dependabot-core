# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/ruby/bundler/force_updater"
require "bundler/compact_index_client"

RSpec.describe Dependabot::UpdateCheckers::Ruby::Bundler::ForceUpdater do
  let(:updater) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      github_access_token: github_token,
      target_version: target_version
    )
  end
  let(:dependency_files) { [gemfile, lockfile] }
  let(:github_token) { "token" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: requirements,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "onfido" }
  let(:current_version) { "0.7.1" }
  let(:target_version) { "0.8.2" }
  let(:requirements) do
    [{ file: "Gemfile", requirement: "~> 0.7.1", groups: [], source: nil }]
  end

  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: "Gemfile")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(content: lockfile_body, name: "Gemfile.lock")
  end

  # TODO: Stub everything so this isn't required
  before { WebMock.allow_net_connect! }

  describe "#force_update" do
    subject { updater.force_update }

    context "when updating the dependency that requires the other" do
      let(:gemfile_body) do
        fixture("ruby", "gemfiles", "version_conflict")
      end
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "version_conflict.lock")
      end
      let(:target_version) { "0.8.8" }
      let(:dependency_name) { "ibandit" }

      its([:version]) { is_expected.to eq(Gem::Version.new("0.8.8")) }
      its([:unlocked_gems]) do
        is_expected.to match_array(%w(ibandit i18n))
      end
    end

    context "when updating the dependency that is required by the other" do
      let(:gemfile_body) do
        fixture("ruby", "gemfiles", "version_conflict_rails")
      end
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "version_conflict_rails.lock")
      end
      let(:target_version) { "5.1.4" }
      let(:dependency_name) { "activesupport" }

      its([:version]) { is_expected.to eq(Gem::Version.new("5.1.4")) }
      its([:unlocked_gems]) do
        is_expected.to match_array(%w(activesupport activemodel))
      end
    end

    context "when two dependencies require the same subdependency" do
      let(:gemfile_body) do
        fixture("ruby", "gemfiles", "version_conflict_mutual_sub")
      end
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "version_conflict_mutual_sub.lock")
      end

      let(:dependency_name) { "rspec" }
      let(:target_version) { "3.6.0" }

      its([:version]) { is_expected.to eq(Gem::Version.new("3.6.0")) }
      its([:unlocked_gems]) do
        is_expected.to match_array(%w(rspec-rails rspec))
      end
    end

    context "when another dependency would need to be downgraded" do
      let(:gemfile_body) do
        fixture("ruby", "gemfiles", "version_conflict_requires_downgrade")
      end
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "version_conflict_requires_downgrade.lock")
      end
      let(:target_version) { "0.8.6" }
      let(:dependency_name) { "i18n" }

      it "raises a resolvability error" do
        expect { updater.force_update }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end
  end
end
