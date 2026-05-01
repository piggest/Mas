#!/usr/bin/env ruby
# 既存の .swift ファイル（ディスク上に作成済み）を Mas.xcodeproj の指定ターゲットに登録する。
# 冪等: 既に登録済みなら何もしない。
#
# 実行方法:
#   GEM_HOME="$HOME/.gem/ruby/2.6.0" ruby scripts/add-source-file.rb <path> <target>
# 例:
#   ruby scripts/add-source-file.rb Mas/Logic/CoordinateMath.swift ScreenshotApp
#   ruby scripts/add-source-file.rb MasTests/PureLogic/CoordinateMathTests.swift MasTests

require "xcodeproj"

PROJECT_PATH = File.expand_path("../Mas.xcodeproj", __dir__)

file_path = ARGV[0] or abort "Usage: ruby scripts/add-source-file.rb <path> <target>"
target_name = ARGV[1] or abort "Usage: ruby scripts/add-source-file.rb <path> <target>"

abs_path = File.expand_path("../#{file_path}", __dir__)
abort "File not found: #{abs_path}" unless File.exist?(abs_path)

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == target_name } \
  or abort "Target '#{target_name}' not found"

# 既存ファイル参照確認（既に登録済みならスキップ）
existing_ref = project.files.find { |f| f.real_path.to_s == abs_path }
if existing_ref
  ref = existing_ref
else
  # ディレクトリ階層をグループとして辿る/作成する
  dir_parts = File.dirname(file_path).split("/")
  group = project.main_group
  dir_parts.each do |part|
    sub = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.path == part }
    if sub.nil?
      sub = group.new_group(part, part)
    end
    group = sub
  end
  ref = group.new_file(File.basename(file_path))
end

# ターゲットの sources ビルドフェーズに登録
unless target.source_build_phase.files.any? { |f| f.file_ref == ref }
  target.add_file_references([ref])
  puts "[ok] Added #{file_path} to target #{target_name}"
else
  puts "[skip] #{file_path} already in target #{target_name}"
end

project.save
