# pi-package-manager

`ppm.sh` is a tiny shell-based package manager prototype for [Pi](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) resources. It installs and updates single-file Pi extensions, skills, and themes from raw URLs or GitHub gists.

This prototype follows the raw URL / gist install flow proposed in [badlogic/pi-mono#4048](https://github.com/badlogic/pi-mono/issues/4048). The goal is for this kind of package-management workflow to eventually become native to Pi.

## Features

- Install Pi extensions (`.ts` / `.js`), skills (`SKILL.md`), and themes (`.json`)
- Install globally to your Pi agent directory or locally to a project `.pi/` directory
- Accept raw URLs, `gist.github.com` URLs, `gist.githubusercontent.com` raw URLs, and `gist:` URLs
- Record source URL, resource type, name, and SHA-256 in Pi settings
- Update managed resources later with drift restoration
- Optionally activate installed themes

## Requirements

`ppm.sh` uses POSIX `sh` plus these commands:

- `curl`
- `node`
- `sha256sum`
- `awk`, `sed`, `grep`, `cut`, `tr`

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
./ppm.sh install --extension --url <url> [options]
./ppm.sh install --skill     --url <url> [options]
./ppm.sh install --theme     --url <url> [options]
./ppm.sh update [options]
```

`gist` is an alias for `install`:

```sh
./ppm.sh gist --extension --url <gist-url> [options]
```

## Options

| Option | Description |
| --- | --- |
| `-l`, `--local` | Install/update project-local resources in `.pi/{extensions,skills,themes}` and `.pi/settings.json` |
| `--all` | With `update`, process both global and local settings |
| `-f`, `--force` | Overwrite an existing installed file/resource |
| `--name <name>` | Output filename for extensions/themes, or skill directory name for skills |
| `--activate` | For themes, set the installed theme in settings |
| `-h`, `--help` | Show help |

## Install examples

Install a global extension from a raw URL:

```sh
./ppm.sh install --extension --url https://gist.githubusercontent.com/user/id/raw/foo.ts
```

Install a skill from a GitHub gist and choose its skill directory name:

```sh
./ppm.sh gist --skill --url https://gist.github.com/user/id --name my-skill
```

Install a project-local theme:

```sh
./ppm.sh install --theme --url https://raw.githubusercontent.com/user/repo/main/theme.json --local
```

Install and activate a theme:

```sh
./ppm.sh install --theme --url https://raw.githubusercontent.com/user/repo/main/theme.json --activate
```

Overwrite an existing resource:

```sh
./ppm.sh install --extension --url https://example.com/extension.ts --name extension.ts --force
```

## Direct usage from GitHub

You can run `ppm.sh` directly from this repository without cloning it by piping the script to `bash` and passing arguments after `--`:

```sh
curl -fsSL https://raw.githubusercontent.com/joakimwinum/pi-package-manager/refs/heads/main/ppm.sh \
  | bash -s -- install --extension --url GIST_URL --name example.ts
```

Examples:

```sh
# Install an extension from a gist or raw URL
curl -fsSL https://raw.githubusercontent.com/joakimwinum/pi-package-manager/refs/heads/main/ppm.sh \
  | bash -s -- install --extension --url GIST_URL --name example.ts

# Install a skill locally in the current project
curl -fsSL https://raw.githubusercontent.com/joakimwinum/pi-package-manager/refs/heads/main/ppm.sh \
  | bash -s -- install --skill --url GIST_URL --name my-skill --local

# Install and activate a theme
curl -fsSL https://raw.githubusercontent.com/joakimwinum/pi-package-manager/refs/heads/main/ppm.sh \
  | bash -s -- install --theme --url GIST_URL --name theme.json --activate

# Update ppm-managed global resources
curl -fsSL https://raw.githubusercontent.com/joakimwinum/pi-package-manager/refs/heads/main/ppm.sh \
  | bash -s -- update
```

## Update examples

Update globally installed ppm-managed resources:

```sh
./ppm.sh update
```

Update project-local resources:

```sh
./ppm.sh update --local
```

Update both global and project-local resources:

```sh
./ppm.sh update --all
```

## Where files are installed

Global installs use `$PI_CODING_AGENT_DIR` when set, otherwise `$HOME/.pi/agent`.

| Resource type | Global path | Local path |
| --- | --- | --- |
| Extension | `$PI_CODING_AGENT_DIR/extensions/<name>` or `$HOME/.pi/agent/extensions/<name>` | `.pi/extensions/<name>` |
| Skill | `$PI_CODING_AGENT_DIR/skills/<name>/SKILL.md` or `$HOME/.pi/agent/skills/<name>/SKILL.md` | `.pi/skills/<name>/SKILL.md` |
| Theme | `$PI_CODING_AGENT_DIR/themes/<name>.json` or `$HOME/.pi/agent/themes/<name>.json` | `.pi/themes/<name>.json` |

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
      "source": "https://gist.github.com/user/id",
      "type": "skill",
      "name": "my-skill",
      "sha256": "..."
    }
  ]
}
```

`ppm.sh update` uses this metadata to download the source again, compare SHA-256 hashes, update changed remote resources, and restore locally modified managed files.

## Resource validation

- Themes must be valid JSON.
- Skills must look like Markdown skill content, starting with frontmatter (`---`) or a top-level heading (`# `).
- Extensions must be named with a `.ts` or `.js` extension.

## Security notes

Only install resources from sources you trust.

- Extensions execute arbitrary code in Pi.
- Skills can instruct the model to perform unsafe actions.
- Themes are data files, but should still be reviewed before use.

After installing resources, run `/reload` in Pi to load them.

## License

MIT. See [LICENSE](LICENSE).
