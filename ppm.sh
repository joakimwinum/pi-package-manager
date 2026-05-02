#!/usr/bin/env sh
# MIT License
#
# Copyright (c) 2026 Joakim Winum Lien
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# ppm.sh - tiny Pi Package Manager prototype for installing/updating single-file Pi resources.
# Interops with Pi packages while handling single-file URLs and GitHub gists.

set -eu

usage() {
  cat <<'USAGE'
Usage:
  ./ppm.sh install --extension gist:<gist-url> --name <file> [options]
  ./ppm.sh install <file-url.ts|js|json|md|markdown> [options]
  ./ppm.sh install git:<repo> [pi-options]
  ./ppm.sh update [pi-options]

Routing:
  gist:<url>            Handled by ppm; requires --extension, --skill, or --theme and --name
  HTTP(S) file URLs     Handled by ppm when the path ends in .ts, .js, .json, .md, or .markdown
                        Type is inferred from the extension: .ts/.js, .json, .md/.markdown
  Other sources         Forwarded to pi, e.g. git:, npm:, and package URLs

Options:
  -l, --local           Use project .pi/{extensions,skills,themes} and .pi/settings.json
      --name <name>     Output filename for extensions/themes, or skill markdown filename
      --force           Overwrite an existing install target
      --activate        For themes, set the installed theme in settings.json
  -h, --help            Show this help

Examples:
  ./ppm.sh install --extension gist:https://gist.githubusercontent.com/user/id/raw --name foo.ts
  ./ppm.sh install --skill gist:https://gist.github.com/user/id --name my-skill.md
  ./ppm.sh install https://raw.githubusercontent.com/user/repo/main/theme.json -l
  ./ppm.sh install git:github.com/user/repo
  ./ppm.sh update

State:
  ppm writes update metadata to the Pi settings file under a top-level "ppm" key.
  Each entry stores source spec, type, name, and sha256 separately so ppm update
  can detect remote changes and restore locally modified files.
USAGE
}

fail() {
  printf 'ppm: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  have "$1" || fail "$1 is required"
}

require_node() {
  require_command node
}

run_pi() {
  require_command pi
  pi "$@"
}

agent_dir() {
  if [ -n "${PI_CODING_AGENT_DIR:-}" ]; then
    printf '%s\n' "$PI_CODING_AGENT_DIR"
  else
    printf '%s\n' "$HOME/.pi/agent"
  fi
}

root_for_scope() {
  scope=$1
  if [ "$scope" = "project" ]; then
    printf '%s\n' ".pi"
  else
    agent_dir
  fi
}

settings_for_scope() {
  scope=$1
  if [ "$scope" = "project" ]; then
    printf '%s\n' ".pi/settings.json"
  else
    printf '%s/settings.json\n' "$(agent_dir)"
  fi
}

download() {
  dl_url=$1
  dl_out=$2
  require_command curl
  curl -fsSL "$dl_url" -o "$dl_out"
}

sha256_file() {
  file=$1
  require_command sha256sum
  sha256sum "$file" | awk '{print $1}'
}

write_file_0644() {
  src=$1
  dst=$2
  mkdir -p "$(dirname "$dst")"
  cat "$src" >"$dst"
  chmod 0644 "$dst" 2>/dev/null || true
}

strip_url_noise() {
  printf '%s\n' "$1" | sed 's/[?#].*$//'
}

source_payload() {
  case "$1" in
    gist:*) printf '%s\n' "${1#gist:}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

basename_from_url() {
  clean=$(strip_url_noise "$(source_payload "$1")")
  base=${clean##*/}
  [ "$base" = "raw" ] && base=""
  printf '%s\n' "$base"
}

is_ppm_file_source() {
  clean=$(strip_url_noise "$(source_payload "$1")")
  case "$clean" in
    *.ts|*.js|*.json|*.md|*.markdown) return 0 ;;
    *) return 1 ;;
  esac
}

is_ppm_source() {
  case "$1" in
    gist:*) return 0 ;;
    http://*|https://*) is_ppm_file_source "$1" ;;
    *) return 1 ;;
  esac
}

name_has_supported_ext() {
  case "$1" in
    *.ts|*.js|*.json|*.md|*.markdown) return 0 ;;
    *) return 1 ;;
  esac
}

resource_type_from_name() {
  case "$1" in
    *.ts|*.js) printf '%s\n' extension ;;
    *.json) printf '%s\n' theme ;;
    *.md|*.markdown) printf '%s\n' skill ;;
    *) return 1 ;;
  esac
}

sanitize_component() {
  # Keep path traversal and shell metacharacters out of installed names.
  safe=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//; s/^\.\.*//')
  [ -n "$safe" ] || fail "could not derive a safe output name; pass --name"
  printf '%s\n' "$safe"
}

without_ext() {
  v=$1
  case "$v" in
    *.markdown) printf '%s\n' "${v%.markdown}" ;;
    *.json) printf '%s\n' "${v%.json}" ;;
    *.md) printf '%s\n' "${v%.md}" ;;
    *.ts) printf '%s\n' "${v%.ts}" ;;
    *.js) printf '%s\n' "${v%.js}" ;;
    *) printf '%s\n' "$v" ;;
  esac
}

source_download_url() {
  input_source=$1
  case "$input_source" in
    gist:*)
      gist_url=${input_source#gist:}
      case "$gist_url" in
        https://gist.github.com/*|http://gist.github.com/*)
          # Convert https://gist.github.com/user/id[/anything] to the gist raw endpoint.
          rest=$(printf '%s' "$gist_url" | sed -E 's#^https?://gist.github.com/##; s/[?#].*$//')
          user=$(printf '%s' "$rest" | cut -d/ -f1)
          id=$(printf '%s' "$rest" | cut -d/ -f2)
          [ -n "$user" ] && [ -n "$id" ] || fail "invalid gist URL: $gist_url"
          printf 'https://gist.githubusercontent.com/%s/%s/raw\n' "$user" "$id"
          ;;
        https://gist.githubusercontent.com/*|http://gist.githubusercontent.com/*)
          printf '%s\n' "$gist_url"
          ;;
        *)
          fail "gist: source must point at github gist: $input_source"
          ;;
      esac
      ;;
    http://*|https://*)
      printf '%s\n' "$input_source"
      ;;
    *)
      fail "ppm sources must be gist:<url> or a direct HTTP(S) file URL: $input_source"
      ;;
  esac
}

json_get_name() {
  file=$1
  require_node
  node - "$file" <<'JS' 2>/dev/null || true
const fs = require("fs");
const value = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).name;
if (typeof value === "string") console.log(value);
JS
}

validate_theme_json() {
  file=$1
  require_node
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$file" >/dev/null \
    || fail "theme must be valid JSON"
}

validate_resource() {
  resource_type=$1
  file=$2
  case "$resource_type" in
    theme)
      validate_theme_json "$file"
      ;;
    skill)
      if ! grep -Eq '^(---|# )' "$file"; then
        fail "skill content should look like markdown skill content (frontmatter or a top-level heading)"
      fi
      ;;
  esac
}

subdir_for_type() {
  resource_type=$1
  case "$resource_type" in
    extension) printf '%s\n' extensions ;;
    skill) printf '%s\n' skills ;;
    theme) printf '%s\n' themes ;;
    *) fail "unknown ppm resource type in settings: $resource_type" ;;
  esac
}

target_for_resource() {
  scope=$1
  resource_type=$2
  resource_name=$3
  root=$(root_for_scope "$scope")
  subdir=$(subdir_for_type "$resource_type")
  case "$resource_type" in
    skill) printf '%s/%s/%s/SKILL.md\n' "$root" "$subdir" "$resource_name" ;;
    *) printf '%s/%s/%s\n' "$root" "$subdir" "$resource_name" ;;
  esac
}

resource_path_for_resource() {
  scope=$1
  resource_type=$2
  resource_name=$3
  root=$(root_for_scope "$scope")
  subdir=$(subdir_for_type "$resource_type")
  case "$resource_type" in
    skill) printf '%s/%s/%s\n' "$root" "$subdir" "$resource_name" ;;
    *) printf '%s/%s/%s\n' "$root" "$subdir" "$resource_name" ;;
  esac
}

settings_upsert_ppm() {
  settings=$1
  source_url=$2
  resource_type=$3
  resource_name=$4
  hash=$5
  require_node
  mkdir -p "$(dirname "$settings")"
  node - "$settings" "$source_url" "$resource_type" "$resource_name" "$hash" <<'JS'
const fs = require("fs");
const [settingsPath, url, type, name, hash] = process.argv.slice(2);
let data = {};
if (fs.existsSync(settingsPath) && fs.statSync(settingsPath).size) {
  data = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
}
const list = Array.isArray(data.ppm) ? data.ppm : [];
let idx = list.findIndex((entry) => entry && entry.source === url && entry.type === type && entry.name === name);
if (idx === -1) {
  idx = list.findIndex((entry) => entry && entry.type === type && entry.name === name);
}
const next = { source: url, type, name, sha256: hash };
if (idx === -1) list.push(next);
else list[idx] = { ...list[idx], ...next };
data.ppm = list;
fs.writeFileSync(settingsPath, JSON.stringify(data, null, 2) + "\n");
JS
}

settings_list_ppm() {
  settings=$1
  [ -f "$settings" ] || return 0
  require_node
  node - "$settings" <<'JS'
const fs = require("fs");
const settingsPath = process.argv[2];
const data = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
for (const entry of Array.isArray(data.ppm) ? data.ppm : []) {
  const source = entry && entry.source;
  if (typeof source !== "string" || !source || !entry.type || !entry.name) continue;
  const hash = entry.sha256 || "";
  process.stdout.write([source, entry.type, entry.name, hash].join("\t") + "\n");
}
JS
}

activate_theme() {
  theme=$1
  settings=$2
  require_node
  mkdir -p "$(dirname "$settings")"
  node - "$settings" "$theme" <<'JS'
const fs = require("fs");
const path = process.argv[2];
const theme = process.argv[3];
let data = {};
if (fs.existsSync(path) && fs.statSync(path).size) {
  data = JSON.parse(fs.readFileSync(path, "utf8"));
}
data.theme = theme;
fs.writeFileSync(path, JSON.stringify(data, null, 2) + "\n");
JS
  printf 'Activated theme "%s" in %s\n' "$theme" "$settings"
}

make_tmp() {
  if have mktemp; then
    mktemp "${TMPDIR:-/tmp}/ppm.XXXXXX"
  else
    printf '%s\n' "${TMPDIR:-/tmp}/ppm.$$"
  fi
}

install_one() {
  scope=$1
  resource_type=$2
  source_url=$3
  resource_name=$4
  force=$5

  raw_url=$(source_download_url "$source_url")
  tmp=$(make_tmp)
  download "$raw_url" "$tmp" || fail "failed to download: $raw_url"
  hash=$(sha256_file "$tmp")
  short_hash=$(printf '%s' "$hash" | cut -c1-12)
  validate_resource "$resource_type" "$tmp"

  target=$(target_for_resource "$scope" "$resource_type" "$resource_name")
  resource_path=$(resource_path_for_resource "$scope" "$resource_type" "$resource_name")

  if [ -e "$resource_path" ] && [ "$force" -ne 1 ]; then
    rm -f "$tmp"
    fail "refusing to overwrite existing $resource_path (use --force)"
  fi

  cat <<EOF
Source:      $source_url
Downloaded:  $raw_url
SHA-256:     $hash
Target:      $target
EOF
  case "$resource_type" in
    extension) printf '%s\n' "Security: remote extensions execute arbitrary code in Pi. Review before use." ;;
    skill) printf '%s\n' "Security: remote skills can instruct the model to perform unsafe actions. Review before use." ;;
    theme) printf '%s\n' "Security: remote themes are data files, but review before use." ;;
  esac

  write_file_0644 "$tmp" "$target"
  rm -f "$tmp"
  settings_upsert_ppm "$(settings_for_scope "$scope")" "$source_url" "$resource_type" "$resource_name" "$hash"

  printf 'Installed %s (%s)\n' "$resource_type" "$short_hash"
  printf 'Recorded %s with sha256=%s in %s\n' "$source_url" "$hash" "$(settings_for_scope "$scope")"
  printf 'Run /reload in Pi to pick up newly installed resources.\n'
}

update_scope() {
  scope=$1
  settings=$(settings_for_scope "$scope")
  if [ ! -f "$settings" ]; then
    printf 'No ppm metadata in %s\n' "$settings"
    return 0
  fi

  list_file=$(make_tmp)
  settings_list_ppm "$settings" >"$list_file"
  if [ ! -s "$list_file" ]; then
    printf 'No ppm-managed resources in %s\n' "$settings"
    rm -f "$list_file"
    return 0
  fi

  tab=$(printf '\t')
  while IFS="$tab" read -r source_url resource_type resource_name old_hash; do
    [ -n "$source_url" ] || continue
    raw_url=$(source_download_url "$source_url")
    tmp=$(make_tmp)
    if ! download "$raw_url" "$tmp"; then
      printf 'Failed to download %s\n' "$source_url" >&2
      rm -f "$tmp"
      continue
    fi
    new_hash=$(sha256_file "$tmp")
    validate_resource "$resource_type" "$tmp"
    target=$(target_for_resource "$scope" "$resource_type" "$resource_name")

    current_hash=""
    if [ -f "$target" ]; then
      current_hash=$(sha256_file "$target")
    fi

    if [ "$new_hash" = "$old_hash" ] && [ "$current_hash" = "$new_hash" ]; then
      printf 'Up to date: %s (%s)\n' "$target" "$(printf '%s' "$new_hash" | cut -c1-12)"
      rm -f "$tmp"
      continue
    fi

    write_file_0644 "$tmp" "$target"
    settings_upsert_ppm "$settings" "$source_url" "$resource_type" "$resource_name" "$new_hash"
    rm -f "$tmp"

    if [ -z "$current_hash" ]; then
      printf 'Installed missing: %s (%s)\n' "$target" "$(printf '%s' "$new_hash" | cut -c1-12)"
    elif [ "$new_hash" != "$old_hash" ]; then
      printf 'Updated remote: %s %s -> %s\n' "$target" "$(printf '%s' "$old_hash" | cut -c1-12)" "$(printf '%s' "$new_hash" | cut -c1-12)"
    else
      printf 'Restored local drift: %s (%s)\n' "$target" "$(printf '%s' "$new_hash" | cut -c1-12)"
    fi
  done <"$list_file"
  rm -f "$list_file"
}

first_install_source() {
  skip_next=0
  for arg do
    if [ "$skip_next" -eq 1 ]; then
      skip_next=0
      continue
    fi
    case "$arg" in
      --name) skip_next=1 ;;
      --name=*|-*) ;;
      gist:*|http://*|https://*|git:*|npm:*|ssh://*|git://*|/*|./*|../*)
        printf '%s\n' "$arg"
        return 0
        ;;
    esac
  done
  return 1
}

ppm_install() {
  resource_type=""
  source=""
  local=0
  force=0
  name=""
  activate=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --extension) [ -z "$resource_type" ] || fail "choose only one resource type"; resource_type=extension; shift ;;
      --skill) [ -z "$resource_type" ] || fail "choose only one resource type"; resource_type=skill; shift ;;
      --theme) [ -z "$resource_type" ] || fail "choose only one resource type"; resource_type=theme; shift ;;
      --name) shift; [ "$#" -gt 0 ] || fail "--name requires a value"; name=$1; shift ;;
      --name=*) name=${1#--name=}; shift ;;
      -l|--local) local=1; shift ;;
      --force) force=1; shift ;;
      --activate) activate=1; shift ;;
      -h|--help) usage; exit 0 ;;
      gist:*) [ -z "$source" ] || fail "source given more than once"; source=$1; shift ;;
      http://*|https://*)
        is_ppm_file_source "$1" || fail "HTTP(S) sources without .ts, .js, .json, .md, or .markdown are handled by pi"
        [ -z "$source" ] || fail "source given more than once"
        source=$1
        shift
        ;;
      -*) fail "unsupported ppm install option: $1" ;;
      *) fail "unknown ppm install argument: $1" ;;
    esac
  done

  [ -n "$source" ] || fail "pass a source: gist:<url> or a direct HTTP(S) file URL"

  base=$(basename_from_url "$source")
  [ -n "$base" ] || base=$(basename_from_url "$(source_download_url "$source")")

  case "$source" in
    gist:*)
      [ -n "$resource_type" ] || fail "gist: installs require one of --extension, --skill, or --theme"
      [ -n "$name" ] || fail "gist: installs require --name <file> with .ts, .js, .json, .md, or .markdown"
      name_has_supported_ext "$name" || fail "gist: --name must end in .ts, .js, .json, .md, or .markdown"
      ext_source=$name
      ;;
    *)
      ext_source=$base
      if [ -z "$resource_type" ]; then
        resource_type=$(resource_type_from_name "$ext_source") || fail "could not infer resource type from URL; use .ts, .js, .json, .md, or .markdown"
      fi
      ;;
  esac

  if [ "$activate" -eq 1 ] && [ "$resource_type" != "theme" ]; then
    fail "--activate only applies to themes"
  fi

  case "$resource_type" in
    extension)
      case "$ext_source" in *.ts|*.js) ;; *) fail "extension sources must use .ts or .js" ;; esac
      ;;
    theme)
      case "$ext_source" in *.json) ;; *) fail "theme sources must use .json" ;; esac
      ;;
    skill)
      case "$ext_source" in *.md|*.markdown) ;; *) fail "skill sources must use .md or .markdown" ;; esac
      ;;
  esac

  case "$resource_type" in
    extension)
      resource_name=${name:-$base}
      [ -n "$resource_name" ] || fail "extension installs need a .ts/.js filename; pass --name foo.ts"
      resource_name=$(sanitize_component "$resource_name")
      case "$resource_name" in *.ts|*.js) ;; *) fail "extension output name must end in .ts or .js" ;; esac
      ;;
    theme)
      resource_name=${name:-$base}
      [ -n "$resource_name" ] || fail "theme installs need a .json filename; pass --name theme.json"
      resource_name=$(sanitize_component "$resource_name")
      case "$resource_name" in *.json) ;; *) resource_name="$resource_name.json" ;; esac
      ;;
    skill)
      resource_name=${name:-$base}
      [ -n "$resource_name" ] || resource_name="skill"
      resource_name=$(sanitize_component "$(without_ext "$resource_name")")
      ;;
  esac

  scope=user
  [ "$local" -eq 1 ] && scope=project

  install_one "$scope" "$resource_type" "$source" "$resource_name" "$force"

  if [ "$activate" -eq 1 ]; then
    target=$(target_for_resource "$scope" "$resource_type" "$resource_name")
    theme_name=$(json_get_name "$target")
    [ -n "$theme_name" ] || theme_name=$(without_ext "$(basename "$target")")
    activate_theme "$theme_name" "$(settings_for_scope "$scope")"
  fi
}

install_dispatch() {
  for arg do
    case "$arg" in
      -h|--help) usage; exit 0 ;;
    esac
  done

  install_source=$(first_install_source "$@" || true)
  case "$install_source" in
    "") run_pi install "$@" ;;
    *)
      if is_ppm_source "$install_source"; then
        ppm_install "$@"
      else
        run_pi install "$@"
      fi
      ;;
  esac
}

ppm_update_scope_from_args() {
  scope=user
  for arg do
    case "$arg" in
      -l|--local) scope=project ;;
      *) return 1 ;;
    esac
  done
  printf '%s\n' "$scope"
  return 0
}

update_dispatch() {
  for arg do
    case "$arg" in
      -h|--help) usage; exit 0 ;;
    esac
  done

  run_pi update "$@"

  update_scope_name=$(ppm_update_scope_from_args "$@" || true)
  if [ -n "$update_scope_name" ]; then
    update_scope "$update_scope_name"
  fi
}

cmd=${1:-}
case "$cmd" in
  install)
    shift
    install_dispatch "$@"
    ;;
  update)
    shift
    update_dispatch "$@"
    ;;
  -h|--help|help|"")
    usage
    ;;
  gist:*|http://*|https://*|git:*|npm:*|ssh://*|git://*|/*|./*|../*)
    install_dispatch "$@"
    ;;
  *)
    run_pi "$@"
    ;;
esac
