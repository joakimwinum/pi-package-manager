# pi-package-manager

`ppm.sh` is a tiny shell-based package manager prototype for [Pi](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) resources. It installs and updates single-file Pi extensions, skills, and themes from direct HTTP(S) file URLs.

This prototype follows the direct URL install flow proposed in [badlogic/pi-mono#4048](https://github.com/badlogic/pi-mono/issues/4048). The goal is for this kind of package-management workflow to eventually become native to Pi.

## Usage

```sh
./ppm.sh install <file-url.ts|js|json|md|markdown> [options]
./ppm.sh update [-l|--local]
```

`ppm.sh` handles HTTP(S) URLs whose paths end in one of these extensions:

- `.ts` or `.js` -> extension
- `.json` -> theme
- `.md` or `.markdown` -> skill

By default, resources are installed into the user Pi agent directory (`$PI_CODING_AGENT_DIR` when set, otherwise `$HOME/.pi/agent`). Use `-l` or `--local` to install into the current project's `.pi` directory instead.

## Options

- `-l`, `--local`: use project-local `.pi/{extensions,skills,themes}` and `.pi/settings.json`.
- `--name <name>`: choose the output filename for extensions/themes, or the skill directory name.
- `--activate`: after installing a theme, set it as the active theme in `settings.json`.
- `-h`, `--help`: show help.

## Examples

```sh
./ppm.sh install https://raw.githubusercontent.com/user/repo/main/extension.ts
./ppm.sh install https://raw.githubusercontent.com/user/repo/main/skill.md --name my-skill.md
./ppm.sh install https://raw.githubusercontent.com/user/repo/main/theme.json -l --activate
./ppm.sh update
```

## Direct usage from GitHub

You can run `ppm.sh` directly from this repository without cloning it by piping the script to `bash` and passing arguments after `--`:

```sh
curl -fsSL https://raw.githubusercontent.com/joakimwinum/pi-package-manager/refs/heads/main/ppm.sh | bash -s -- install https://raw.githubusercontent.com/user/repo/main/extension.ts --name example.ts
```

## Update metadata

`ppm.sh` records managed resources in the relevant Pi `settings.json` file under a top-level `ppm` key. Each entry stores the source URL, resource type, resource name, and SHA-256 hash so `ppm.sh update` can detect remote changes and restore locally modified files.

## Security notes

Only install resources from sources you trust.

- Extensions execute arbitrary code in Pi.
- Skills can instruct the model to perform unsafe actions.
- Themes are data files, but should still be reviewed before use.

After installing resources, run `/reload` in Pi to load them.

## License

MIT. See [LICENSE](LICENSE).
