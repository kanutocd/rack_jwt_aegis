# frozen_string_literal: true

require 'test_helper'
require 'open3'

class CLITest < Minitest::Test
  def setup
    @cli_path = File.join(__dir__, '..', 'exe', 'rack_jwt_aegis')
  end

  def test_cli_help_command
    stdout, stderr, status = Open3.capture3("ruby #{@cli_path} --help")

    assert_predicate status, :success?
    assert_empty stderr
    assert_includes stdout, '🛡️  Rack JWT Aegis CLI'
    assert_includes stdout, 'USAGE:'
    assert_includes stdout, 'COMMANDS:'
  end

  def test_cli_version_command
    stdout, stderr, status = Open3.capture3("ruby #{@cli_path} version")

    assert_predicate status, :success?
    assert_empty stderr
    assert_match(/rack_jwt_aegis \d+\.\d+\.\d+/, stdout)
  end

  def test_cli_secret_generation_default
    stdout, stderr, status = Open3.capture3("ruby #{@cli_path} secret")

    assert_predicate status, :success?
    assert_empty stderr
    assert_includes stdout, '🛡️  Rack JWT Aegis - Secret Generator'
    assert_includes stdout, 'Length: 64 bytes'
    assert_includes stdout, 'Format: hex'
    assert_includes stdout, 'Entropy: ~512.0 bits'
  end

  def test_cli_secret_generation_quiet_mode
    stdout, stderr, status = Open3.capture3("ruby #{@cli_path} secret --quiet")

    assert_predicate status, :success?
    assert_empty stderr
    # Should only contain the secret (128 hex characters for 64 bytes)
    secret = stdout.strip

    assert_equal 128, secret.length
    assert_match(/\A[a-f0-9]+\z/, secret)
  end

  def test_cli_secret_generation_base64 # rubocop:disable Naming/VariableNumber
    stdout, stderr, status = Open3.capture3("ruby #{@cli_path} secret --format base64 --quiet")

    assert_predicate status, :success?
    assert_empty stderr
    # Base64 encoded 64 bytes should be about 88 characters (with padding)
    secret = stdout.strip

    assert_operator secret.length, :>=, 85
    assert_match(%r{\A[A-Za-z0-9+/]+=*\z}, secret)
  end

  def test_cli_secret_generation_env_format
    stdout, stderr, status = Open3.capture3("ruby #{@cli_path} secret --env --quiet")

    assert_predicate status, :success?
    assert_empty stderr
    assert_match(/\AJWT_SECRET=[a-f0-9]{128}\z/, stdout.strip)
  end

  def test_cli_secret_generation_custom_length
    stdout, stderr, status = Open3.capture3("ruby #{@cli_path} secret --length 32 --quiet")

    assert_predicate status, :success?
    assert_empty stderr
    # 32 bytes should be 64 hex characters
    secret = stdout.strip

    assert_equal 64, secret.length
    assert_match(/\A[a-f0-9]+\z/, secret)
  end

  def test_cli_secret_generation_multiple_secrets
    stdout, stderr, status = Open3.capture3("ruby #{@cli_path} secret --count 3 --quiet")

    assert_predicate status, :success?
    assert_empty stderr
    secrets = stdout.strip.split("\n")

    assert_equal 3, secrets.length
    secrets.each do |secret|
      assert_equal 128, secret.length
      assert_match(/\A[a-f0-9]+\z/, secret)
    end
  end

  def test_cli_invalid_command
    stdout, stderr, status = Open3.capture3("ruby #{@cli_path} invalid")

    assert_predicate status, :success? # Shows help, doesn't error
    assert_empty stderr
    assert_includes stdout, 'USAGE:'
  end

  def test_cli_secret_with_invalid_format
    _stdout, stderr, status = Open3.capture3("ruby #{@cli_path} secret --format invalid")

    refute_predicate status, :success?
    assert_includes stderr, 'invalid argument'
  end

  def test_cli_executable_file_exists
    assert_path_exists @cli_path, "CLI executable should exist at #{@cli_path}"
    assert File.executable?(@cli_path), 'CLI file should be executable'
  end
end
