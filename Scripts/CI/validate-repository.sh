#!/usr/bin/env bash

set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "$repository_root"

required_files=(
    ".agents/skills/develop-yamalens/SKILL.md"
    ".agents/skills/develop-yamalens/agents/openai.yaml"
    ".agents/skills/develop-yamalens/references/ci-strategy.md"
    ".agents/skills/develop-yamalens/references/delivery-checklist.md"
    ".agents/skills/develop-yamalens/references/git-workflow.md"
    ".agents/skills/develop-yamalens/references/liquid-glass-ui-rules.md"
    ".agents/skills/develop-yamalens/references/project-structure.md"
    ".agents/skills/develop-yamalens/references/swift-coding-rules.md"
    ".agents/skills/develop-yamalens/references/testing-strategy.md"
    ".github/pull_request_template.md"
    ".gitignore"
    "AGENTS.md"
    "Data/Bootstrap/tanzawa-bootstrap-v1.json"
    "Data/SourceManifests/tanzawa-bootstrap-v1.yaml"
    "Tools/OfflinePackageBuilder/build_bootstrap.py"
    "YamaLens/YamaLens/Resources/Bootstrap/bootstrap.sqlite"
    "doc/YamaLens_UI設計書.md"
    "doc/YamaLens_事前決定事項.md"
    "doc/YamaLens_基本設計書.md"
)

for required_file in "${required_files[@]}"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Required file is missing: $required_file" >&2
        exit 1
    fi
done

python3 Tools/OfflinePackageBuilder/build_bootstrap.py \
    --input Data/Bootstrap/tanzawa-bootstrap-v1.json \
    --output YamaLens/YamaLens/Resources/Bootstrap/bootstrap.sqlite \
    --verify-only

if ! compgen -G 'doc/*要求仕様書.md' > /dev/null; then
    echo "Required specification document is missing: doc/*要求仕様書.md" >&2
    exit 1
fi

ruby - ".agents/skills/develop-yamalens/SKILL.md" <<'RUBY'
require "yaml"

skill_path = ARGV.fetch(0)
skill_text = File.read(skill_path, encoding: "UTF-8")
match = skill_text.match(/\A---\n(.*?)\n---\n/m)
abort("SKILL.md frontmatter is missing") unless match

frontmatter = YAML.safe_load(match[1], aliases: false)
abort("SKILL.md frontmatter must be a mapping") unless frontmatter.is_a?(Hash)
abort("SKILL.md frontmatter must contain only name and description") unless frontmatter.keys.sort == ["description", "name"]
abort("SKILL.md name is invalid") unless frontmatter["name"] == "develop-yamalens"
description = frontmatter["description"]
abort("SKILL.md description is invalid") unless description.is_a?(String) && !description.strip.empty?

puts "SKILL.md frontmatter: OK"
RUBY

ruby <<'RUBY'
markdown_files = Dir.glob("**/*.md", File::FNM_DOTMATCH).reject { |path| path.start_with?(".git/") }
missing_links = []

markdown_files.each do |markdown_file|
    text = File.read(markdown_file, encoding: "UTF-8")
    text.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |raw_target|
        target = raw_target.strip
        target = target[1...-1] if target.start_with?("<") && target.end_with?(">")
        next if target.match?(/\A(?:https?:|mailto:|#|\/)/)

        target = target.split("#", 2).first
        next if target.nil? || target.empty?

        resolved = File.expand_path(target, File.dirname(markdown_file))
        missing_links << "#{markdown_file}: #{target}" unless File.exist?(resolved)
    end
end

unless missing_links.empty?
    warn "Missing relative Markdown links:"
    missing_links.each { |link| warn "  #{link}" }
    exit 1
end

puts "Relative Markdown links: OK"
RUBY

while IFS= read -r tracked_file; do
    case "$tracked_file" in
        .env.example)
            ;;
        .DS_Store|*/.DS_Store|.env|.env.*|*.p8|*.mobileprovision|*.xcuserstate|*/xcuserdata/*|*.xcresult|*.xcresult/*|Data/Generated/*)
            echo "Forbidden tracked file: $tracked_file" >&2
            exit 1
            ;;
    esac
done < <(git ls-files)

if git grep -n -I -E '^(<<<<<<< |>>>>>>> )' -- .; then
    echo "Unresolved Git conflict marker found" >&2
    exit 1
fi

if git rev-parse --verify HEAD^ > /dev/null 2>&1; then
    git diff --check HEAD^ HEAD
else
    git show --check --oneline --no-renames HEAD
fi

echo "Repository validation: OK"
