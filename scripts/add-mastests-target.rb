#!/usr/bin/env ruby
# MasTests ユニットテストターゲットを Mas.xcodeproj に追加するスクリプト。
# 冪等: 既に MasTests ターゲットがあれば何もしない。
#
# 実行方法:
#   GEM_HOME="$HOME/.gem/ruby/2.6.0" ruby scripts/add-mastests-target.rb

require "xcodeproj"

PROJECT_PATH = File.expand_path("../Mas.xcodeproj", __dir__)
TEST_TARGET_NAME = "MasTests"
TEST_DIR_NAME = "MasTests"

project = Xcodeproj::Project.open(PROJECT_PATH)

# 既存チェック
if project.targets.any? { |t| t.name == TEST_TARGET_NAME }
  puts "[skip] '#{TEST_TARGET_NAME}' target already exists"
  exit 0
end

# ホストアプリのターゲット
host_target = project.targets.find { |t| t.name == "ScreenshotApp" } \
  or abort "ScreenshotApp target not found"

deployment_target = host_target.build_configurations.first.build_settings["MACOSX_DEPLOYMENT_TARGET"] || "13.0"

# テストターゲット作成
test_target = project.new_target(
  :unit_test_bundle,
  TEST_TARGET_NAME,
  :osx,
  deployment_target,
  project.products_group,
  :swift
)

# ホストアプリに依存させる（test_target_for_target 相当）
test_target.add_dependency(host_target)

# 各 build configuration の設定を整える
test_target.build_configurations.each do |config|
  bs = config.build_settings
  bs["PRODUCT_BUNDLE_IDENTIFIER"]      = "com.example.MasTests"
  bs["MACOSX_DEPLOYMENT_TARGET"]       = deployment_target
  bs["SWIFT_VERSION"]                  = host_target.build_configurations.first.build_settings["SWIFT_VERSION"] || "5.8"
  bs["GENERATE_INFOPLIST_FILE"]        = "YES"
  bs["CURRENT_PROJECT_VERSION"]        = "1"
  bs["MARKETING_VERSION"]              = "1.0"
  bs["TEST_HOST"]                      = "$(BUILT_PRODUCTS_DIR)/Mas.app/Contents/MacOS/Mas"
  bs["BUNDLE_LOADER"]                  = "$(TEST_HOST)"
  bs["LD_RUNPATH_SEARCH_PATHS"]        = ["@loader_path/../Frameworks", "@loader_path/../Frameworks"]
  bs["CODE_SIGN_STYLE"]                = "Manual"
  bs["CODE_SIGN_IDENTITY"]             = "Mas Development"
  bs["DEVELOPMENT_TEAM"]               = host_target.build_configurations.find { |c| c.name == config.name }&.build_settings&.dig("DEVELOPMENT_TEAM") || ""
end

# MasTests グループとファイル参照
tests_group = project.main_group.find_subpath(TEST_DIR_NAME, true)
tests_group.set_source_tree("<group>")
tests_group.set_path(TEST_DIR_NAME)

# SmokeTests.swift をプロジェクトに登録
smoke_file = tests_group.new_file("SmokeTests.swift")
test_target.add_file_references([smoke_file])

# スキームに test action を追加（既存 ScreenshotApp スキームを更新）
schemes_dir = Xcodeproj::XCScheme.shared_data_dir(PROJECT_PATH)
scheme_path = File.join(schemes_dir, "ScreenshotApp.xcscheme")
if File.exist?(scheme_path)
  scheme = Xcodeproj::XCScheme.new(scheme_path)
  testable = Xcodeproj::XCScheme::TestAction::TestableReference.new(test_target)
  scheme.test_action.add_testable(testable)
  scheme.save_as(PROJECT_PATH, "ScreenshotApp", true)
  puts "[ok] Added MasTests to ScreenshotApp scheme test action"
else
  puts "[warn] ScreenshotApp scheme not found at #{scheme_path}, you may need to add MasTests manually"
end

project.save
puts "[ok] Added '#{TEST_TARGET_NAME}' target to #{PROJECT_PATH}"
