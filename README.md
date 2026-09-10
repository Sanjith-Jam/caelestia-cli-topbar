# CLI-TOP College tab for Caelestia / Omarchy

This repository packages the College dashboard tab used with [CLI-TOP](https://github.com/avinashnedunuri/cli-top) on an Omarchy/Caelestia desktop.

It provides:

- a College tab with today/tomorrow/day-after timetable navigation;
- attendance and digital-assessment views;
- assignments sorted by deadline, with due-today items first and highlighted;
- a local cache so the last successful data appears immediately after a shell restart;
- serialized CLI-TOP requests and a 30-minute automatic refresh while the dashboard is open.

No credentials, `.env` files, cookies, session files, or portal data are included.

## Requirements

- Omarchy with Caelestia/Quickshell;
- a working CLI-TOP installation and login;
- the CLI-TOP binary at `~/cli-top/cli-top`, or `CAELESTIA_CLI_TOP_BIN` set to its path.

## Install

Run this repository's installer, then merge the two small `Content.qml` additions described below:

```sh
./scripts/install.sh
```

The installer backs up an existing `CliTopTab.qml` and wrapper before replacing them. It does not touch CLI-TOP credentials.

Add the College entry to `~/.config/quickshell/caelestia/modules/dashboard/Content.qml` inside `dashboardTabs`:

```qml
{
    component: cliTopComponent,
    iconName: "school",
    text: qsTr("College"),
    enabled: true,
    persistent: true
},
```

Then add the component near the other `Component` declarations:

```qml
Component {
    id: cliTopComponent

    CliTopTab {
        screenState: root.screenState
    }
}
```

`CliTopTab.qml` is installed beside `Content.qml`, so no import-path change is needed. Restart the shell after merging:

```sh
caelestia shell -k
caelestia shell -d
```

On the first opening, the tab performs its normal serialized refresh and writes `~/.cache/caelestia/cli-top-dashboard.json`. Later openings render from that cache and refresh in the background.

## CLI-TOP path overrides

The wrapper defaults to `~/cli-top/cli-top`. Use these variables for another layout:

```sh
export CAELESTIA_CLI_TOP_BIN="$HOME/path/to/cli-top"
export CAELESTIA_CLI_TOP_PATH="$HOME/.local/bin/caelestia-cli-top"
```

Put them in the environment inherited by Quickshell (for example, the Omarchy/Hyprland environment configuration), then restart the shell.

## Safety

Do not commit `~/.config/cli-top/`, `.env`, portal cookies, or CLI-TOP session files. If the portal reports an authentication failure or lockout, stop refreshing, use the portal's normal password-reset flow, and only log in again manually.
