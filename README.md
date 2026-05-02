# pi-package-manager

`ppm.sh` is a tiny shell-based package manager prototype for [Pi](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) resources. It installs and updates single-file Pi extensions, skills, and themes from direct HTTP(S) file URLs or GitHub gists.

This prototype follows the direct URL / gist install flow proposed in [badlogic/pi-mono#4048](https://github.com/badlogic/pi-mono/issues/4048). The goal is for this kind of package-management workflow to eventually become native to Pi.

## Features

- Installs single-file Pi extensions (`.ts`, `.js`), themes (`.json`), and skills (`.md`, `.markdown`).
- Supports direct HTTP(S) file URLs and GitHub gists using `gist:<url>`.
- Infers resource type from direct file URL extensions.
- Records source and SHA-256 metadata so managed resources can be updated later.
- Supports global installs and project-local installs with `--local`.
- Can activate installed themes with `--activate`.
- Forwards normal Pi package sources such as `git:` and `npm:` to `pi install`.

## Requirements

- POSIX-compatible shell.
- `curl` for downloads.
- `node` for JSON/settings updates and theme validation.
- `sha256sum` for update metadata.
- Standard Unix tools used by the script: `awk`, `grep`, `sed`, `cut`, `dirname`, `basename`, `mktemp`.
- The `pi` CLI on `PATH` for delegated package installs and `ppm.sh update`.

## Installation

Clone this repository or download `ppm.sh` directly:

```sh
chmod +x ppm.sh
```

Run it from this repository:

```sh
./ppm.sh --help
```

Or place it somewhere on your `PATH`:

```sh
sudo cp ppm.sh /usr/local/bin/ppm
ppm --help
```

## Usage

```sh
./ppm.sh install --extension gist:<gist-url> --name <file.ts|file.js> [options]
./ppm.sh install --skill gist:<gist-url> --name <skill.md|skill.markdown> [options]
./ppm.sh install --theme gist:<gist-url> --name <theme.json> [options]
./ppm.sh install <https-url-to-file.ts|js|json|md|markdown> [options]
./ppm.sh install git:<repo> [pi-options]
./ppm.sh update [--local]
```

Routing rules:

- `gist:<url>` is handled by `ppm.sh` and requires one of `--extension`, `--skill`, or `--theme` plus `--name`.
- Direct HTTP(S) URLs ending in `.ts`, `.js`, `.json`, `.md`, or `.markdown` are handled by `ppm.sh`.
- Other install sources are forwarded to `pi install`.
- Other commands are forwarded to `pi`.

## Options

- `--extension` installs an extension. Required for gist extension installs.
- `--skill` installs a skill. Required for gist skill installs.
- `--theme` installs a theme. Required for gist theme installs.
- `--name <name>` sets the installed name. Required for gist installs.
- `-l`, `--local` installs to the current project's `.pi` directory and records metadata in `.pi/settings.json`.
- `--activate` activates an installed theme by writing `theme` in the matching settings file.
- `-h`, `--help` shows help.

## Install examples

```sh
# Install an extension from a gist
./ppm.sh install --extension gist:https://gist.github.com/user/gist-id --name example.ts

# Install a skill from a gist into the current project
./ppm.sh install --skill gist:https://gist.github.com/user/gist-id --name my-skill.md --local

# Install a global extension from a direct raw file URL
./ppm.sh install https://raw.githubusercontent.com/user/repo/main/example.ts

# Install a local skill from a direct raw file URL
./ppm.sh install https://raw.githubusercontent.com/user/repo/main/my-skill.md --local

# Install and activate a theme
./ppm.sh install https://raw.githubusercontent.com/user/repo/main/theme.json --activate

# Forward a normal Pi package install to pi
./ppm.sh install git:github.com/user/repo
```

## Direct usage from GitHub

You can run `ppm.sh` directly from this repository without cloning it by piping the script to `sh` or `bash` and passing arguments after `--`:

```sh
curl -fsSL https://raw.githubusercontent.com/joakimwinum/pi-package-manager/refs/heads/main/ppm.sh \
  | sh -s -- install --extension gist:https://gist.github.com/user/gist-id --name example.ts
```

Examples:

```sh
# Install an extension from a gist
curl -fsSL https://raw.githubusercontent.com/joakimwinum/pi-package-manager/refs/heads/main/ppm.sh \
  | sh -s -- install --extension gist:https://gist.github.com/user/gist-id --name example.ts

# Install a skill locally in the current project
curl -fsSL https://raw.githubusercontent.com/joakimwinum/pi-package-manager/refs/heads/main/ppm.sh \
  | sh -s -- install --skill gist:https://gist.github.com/user/gist-id --name my-skill.md --local

# Install and activate a theme from a direct file URL
curl -fsSL https://raw.githubusercontent.com/joakimwinum/pi-package-manager/refs/heads/main/ppm.sh \
  | sh -s -- install https://raw.githubusercontent.com/user/repo/main/theme.json --activate

# Update ppm-managed global resources
curl -fsSL https://raw.githubusercontent.com/joakimwinum/pi-package-manager/refs/heads/main/ppm.sh \
  | sh -s -- update
```

## Update examples

```sh
# Run pi update, then update ppm-managed global resources
./ppm.sh update

# Run pi update --local, then update ppm-managed project-local resources
./ppm.sh update --local

# Pi-specific update arguments are delegated to pi only
./ppm.sh update self
```

`ppm.sh update` downloads each recorded source again, validates it, compares SHA-256 hashes, and writes the remote content when the remote changed, the local file was modified, or the local file is missing.

## Where files are installed

Global installs use `$PI_CODING_AGENT_DIR` when it is set, otherwise `$HOME/.pi/agent`:

```text
$PI_CODING_AGENT_DIR/extensions/<name>.ts
$PI_CODING_AGENT_DIR/themes/<name>.json
$PI_CODING_AGENT_DIR/skills/<name>/SKILL.md
```

Project-local installs use the current project's `.pi` directory:

```text
.pi/extensions/<name>.ts
.pi/themes/<name>.json
.pi/skills/<name>/SKILL.md
```

For skills, `--name my-skill.md` installs to `skills/my-skill/SKILL.md`.

## Metadata

`ppm.sh` writes update metadata to the Pi settings file under a top-level `ppm` key.

Global metadata is written to:

```text
$PI_CODING_AGENT_DIR/settings.json
```

or, if `PI_CODING_AGENT_DIR` is not set:

```text
$HOME/.pi/agent/settings.json
```

Local metadata is written to:

```text
.pi/settings.json
```

Example metadata:

```json
{
  "ppm": [
    {
      "source": "gist:https://gist.github.com/user/gist-id",
      "type": "skill",
      "name": "my-skill",
      "sha256": "..."
    }
  ]
}
```

Each entry stores the original source spec, resource type, installed resource name, and last downloaded SHA-256. `ppm.sh update` uses this metadata to download the source again, compare hashes, update changed remote resources, and restore locally modified managed files.

When `--activate` is used for a theme, `ppm.sh` also writes the selected theme name to the same settings file's top-level `theme` key.

## Resource validation

- Themes must be valid JSON.
- Skills must look like Markdown skill content: frontmatter (`---`) or a top-level heading (`# `).
- Extensions are downloaded as-is; review them before installing.

## Security notes

Only install resources from sources you trust.

- Extensions execute arbitrary code in Pi.
- Skills can instruct the model to perform unsafe actions.
- Themes are data files, but should still be reviewed before use.

After installing resources, run `/reload` in Pi to load them.

## License

MIT. See [LICENSE](LICENSE).
