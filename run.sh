#!/usr/bin/env bash
set -e

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUBY="$HERE/deps/ruby/bin/ruby"

VERSION="$("$RUBY" -rrbconfig -e 'print RbConfig::CONFIG["ruby_version"]')"

export GEM_HOME="$HERE/deps/ruby/lib/ruby/gems/$VERSION"
export GEM_PATH="$GEM_HOME"
export PATH="$HERE/deps/ruby/bin:$PATH"

cd "$HERE"
exec "$RUBY" main.rb "$@"
