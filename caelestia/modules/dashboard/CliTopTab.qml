pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property ScreenState screenState

    readonly property string cliPath: Quickshell.env("CAELESTIA_CLI_TOP_PATH") || `${Paths.home}/.local/bin/caelestia-cli-top`
    readonly property string cachePath: `${Paths.cache}/cli-top-dashboard.json`
    readonly property bool portalEnabled: true
    property int dayOffset: 0
    property var scheduleRows: []
    property var attendanceRows: []
    property var daRows: []
    property string scheduleNote: ""
    property string scheduleError: ""
    property string attendanceError: ""
    property string daError: ""
    property bool scheduleLoading: false
    property bool attendanceLoading: false
    property bool daLoading: false
    property bool refreshChain: false
    property bool autoRefreshReady: false
    property bool cacheLoaded: false
    property string scheduleRequestKey: ""
    property var pendingScheduleRows: []
    property bool scheduleResponseRejected: false
    property bool attendanceResponseRejected: false
    property bool daResponseRejected: false
    property var cacheData: ({ version: 1, schedules: ({}), attendance: [], assignments: [], updatedAt: 0 })

    readonly property color cSurface: Colours.tPalette.m3surfaceContainer
    readonly property color cSurfaceHigh: Colours.tPalette.m3surfaceContainerHigh
    readonly property color cOnSurface: Colours.palette.m3onSurface
    readonly property color cOnSurfaceVariant: Colours.palette.m3onSurfaceVariant
    readonly property color cPrimary: Colours.palette.m3primary
    readonly property color cSecondary: Colours.palette.m3secondary
    readonly property color cTertiary: Colours.palette.m3tertiary
    readonly property color cError: Colours.palette.m3error

    implicitWidth: 920
    implicitHeight: 620

    function stripFormatting(value) {
        return value
            .replace(/\x1b\]8;;[^\x07]*\x07/g, "")
            .replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, "")
            .replace(/\r/g, "");
    }

    function tableRows(value, expectedColumns) {
        const rows = [];
        const lines = stripFormatting(value).split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i];
            if (line.indexOf("│") < 0 || line.indexOf("─") >= 0)
                continue;
            const columns = line.split("│").map(part => part.trim());
            if (columns.length !== expectedColumns || columns[0] === "TIME" || columns[0] === "INDEX")
                continue;
            rows.push(columns);
        }
        return rows;
    }

    function portalError(value, fallback) {
        const clean = stripFormatting(value);
        if (clean.indexOf("Maximum Fail Attempts Reached") >= 0)
            return qsTr("VTOP login locked — reset your password in VTOP");
        if (clean.indexOf("Please login first") >= 0)
            return qsTr("CLI-TOP login required");
        return fallback;
    }

    function refreshSchedule() {
        if (!portalEnabled)
            return;
        if (scheduleProcess.running)
            return;
        if (isWeekend()) {
            scheduleRows = [];
            scheduleError = "";
            scheduleNote = qsTr("No classes scheduled on weekends");
            scheduleLoading = false;
            if (refreshChain)
                refreshAttendance();
            return;
        }
        const commands = ["today", "tomorrow", "dayafter"];
        scheduleLoading = true;
        scheduleError = "";
        scheduleNote = "";
        scheduleRequestKey = selectedDateKey();
        pendingScheduleRows = [];
        scheduleResponseRejected = false;
        scheduleProcess.command = ["env", "TERM=dumb", "NO_COLOR=1", cliPath, commands[dayOffset]];
        scheduleProcess.running = true;
    }

    function refreshAttendance() {
        if (!portalEnabled)
            return;
        if (attendanceProcess.running)
            return;
        attendanceLoading = true;
        attendanceError = "";
        attendanceResponseRejected = false;
        attendanceProcess.running = true;
    }

    function refreshDa() {
        if (!portalEnabled)
            return;
        if (daProcess.running)
            return;
        daLoading = true;
        daError = "";
        daResponseRejected = false;
        daProcess.running = true;
    }

    function refreshAll() {
        if (!portalEnabled)
            return;
        if (scheduleProcess.running || attendanceProcess.running || daProcess.running)
            return;
        refreshChain = true;
        refreshSchedule();
    }

    function moveDay(delta) {
        const next = Math.max(0, Math.min(2, dayOffset + delta));
        if (next === dayOffset)
            return;
        dayOffset = next;
        restoreScheduleFromCache();
        refreshSchedule();
    }

    function selectedDateValue() {
        const value = new Date();
        value.setDate(value.getDate() + dayOffset);
        return value;
    }

    function selectedDate() {
        return selectedDateValue().toLocaleDateString(Qt.locale(), "dddd, MMMM d");
    }

    function isWeekend() {
        const day = selectedDateValue().getDay();
        return day === 0 || day === 6;
    }

    function dayName() {
        if (dayOffset === 0)
            return qsTr("Today");
        if (dayOffset === 1)
            return qsTr("Tomorrow");
        return qsTr("Day after");
    }

    function percentageColour(value) {
        const number = parseInt(value);
        if (isNaN(number))
            return cOnSurfaceVariant;
        if (number <= 75)
            return cError;
        if (number < 80)
            return cTertiary;
        return cPrimary;
    }

    function deadlineTimestamp(value) {
        if (!value || value === "N/A")
            return 8640000000000000;
        const clean = String(value).trim().replace(/,/g, "").replace(/\s+/g, " ");
        const months = {
            Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5,
            Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11
        };
        let match = clean.match(/^(\d{1,2})[-\s/]([A-Za-z]{3,9})[-\s/](\d{4})(?:\s+(\d{1,2}):(\d{2})(?:\s*(AM|PM))?)?/i);
        if (match) {
            const monthKey = match[2].slice(0, 3).toLowerCase();
            const monthNames = Object.keys(months);
            for (let i = 0; i < monthNames.length; ++i) {
                if (monthNames[i].toLowerCase() === monthKey) {
                    let hour = parseInt(match[4] || "0");
                    const minute = parseInt(match[5] || "0");
                    const meridiem = (match[6] || "").toUpperCase();
                    if (meridiem === "PM" && hour < 12) hour += 12;
                    if (meridiem === "AM" && hour === 12) hour = 0;
                    return new Date(parseInt(match[3]), months[monthNames[i]], parseInt(match[1]), hour, minute).getTime();
                }
            }
        }
        match = clean.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})/);
        if (match)
            return new Date(parseInt(match[3]), parseInt(match[2]) - 1, parseInt(match[1])).getTime();
        match = clean.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})/);
        if (match)
            return new Date(parseInt(match[1]), parseInt(match[2]) - 1, parseInt(match[3])).getTime();
        return 8639999999999999;
    }

    function isDeadlineToday(value) {
        const now = new Date();
        const deadline = new Date(deadlineTimestamp(value));
        return deadline.getFullYear() === now.getFullYear()
            && deadline.getMonth() === now.getMonth()
            && deadline.getDate() === now.getDate();
    }

    function sortAssignments(rows) {
        return rows.slice().sort((left, right) => {
            const leftDueToday = isDeadlineToday(left.deadline);
            const rightDueToday = isDeadlineToday(right.deadline);
            if (leftDueToday !== rightDueToday)
                return leftDueToday ? -1 : 1;
            const dateDifference = deadlineTimestamp(left.deadline) - deadlineTimestamp(right.deadline);
            return dateDifference !== 0 ? dateDifference : left.subject.localeCompare(right.subject);
        });
    }

    function selectedDateKey() {
        const date = selectedDateValue();
        const month = String(date.getMonth() + 1).padStart(2, "0");
        const day = String(date.getDate()).padStart(2, "0");
        return `${date.getFullYear()}-${month}-${day}`;
    }

    function restoreScheduleFromCache() {
        const schedules = cacheData.schedules || {};
        scheduleRows = schedules[selectedDateKey()] || [];
        scheduleError = "";
    }

    function saveCache() {
        cacheData.updatedAt = Date.now();
        cacheStorage.setText(JSON.stringify(cacheData));
    }

    function cacheSchedule(key, rows) {
        const schedules = Object.assign({}, cacheData.schedules || {});
        schedules[key] = rows;
        cacheData.schedules = schedules;
        saveCache();
    }

    FileView {
        id: cacheStorage
        path: root.cachePath
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed && parsed.version === 1) {
                    root.cacheData = parsed;
                    root.restoreScheduleFromCache();
                    root.attendanceRows = parsed.attendance || [];
                    root.daRows = root.sortAssignments(parsed.assignments || []);
                    root.autoRefreshReady = root.scheduleRows.length > 0
                        || root.attendanceRows.length > 0 || root.daRows.length > 0;
                }
            } catch (error) {
                console.warn("CLI-TOP cache could not be parsed:", error);
            }
            root.cacheLoaded = true;
        }
        onLoadFailed: err => {
            root.cacheLoaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(JSON.stringify(root.cacheData)));
        }
    }

    // Load once when the College tab is instantiated. Further automatic
    // refreshes are deliberately infrequent and only enabled after success.
    Timer {
        interval: 1000
        running: root.cacheLoaded
        repeat: false
        onTriggered: root.refreshAll()
    }

    Timer {
        interval: 30 * 60 * 1000
        running: root.screenState.dashboard && root.autoRefreshReady
        repeat: true
        onTriggered: root.refreshAll()
    }

    Process {
        id: scheduleProcess
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const clean = root.stripFormatting(text);
                root.scheduleResponseRejected = clean.indexOf("Maximum Fail Attempts Reached") >= 0
                    || clean.indexOf("Please login first") >= 0;
                const parsed = root.tableRows(clean, 6);
                root.pendingScheduleRows = parsed.map(parts => ({
                    time: parts[0], subject: parts[1], venue: parts[2],
                    percentage: parts[3], leverage: parts[4], skippable: parts[5]
                }));
                if (root.scheduleRequestKey === root.selectedDateKey())
                    root.scheduleRows = root.pendingScheduleRows;
                const lines = clean.split("\n");
                for (let i = 0; i < lines.length; ++i) {
                    if (lines[i].indexOf(" follows ") >= 0) {
                        root.scheduleNote = lines[i].trim();
                        break;
                    }
                }
                root.scheduleLoading = false;
                if (root.pendingScheduleRows.length === 0) {
                    root.scheduleError = root.portalError(clean, qsTr("No classes found for this day"));
                    if (clean.indexOf("Maximum Fail Attempts Reached") >= 0 || clean.indexOf("Please login first") >= 0)
                        root.refreshChain = false;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    console.warn("CLI-TOP timetable:", root.stripFormatting(text).trim());
                    root.scheduleError = qsTr("Could not load the timetable");
                }
            }
        }
        onExited: code => {
            root.scheduleLoading = false;
            if (code !== 0) {
                root.scheduleError = qsTr("CLI-TOP timetable request failed");
                root.refreshChain = false;
            } else if (!root.scheduleResponseRejected) {
                if (root.scheduleRequestKey === root.selectedDateKey())
                    root.scheduleRows = root.pendingScheduleRows;
                root.cacheSchedule(root.scheduleRequestKey, root.pendingScheduleRows);
                if (root.refreshChain)
                    root.refreshAttendance();
            } else {
                root.restoreScheduleFromCache();
                root.refreshChain = false;
            }
        }
    }

    Process {
        id: attendanceProcess
        command: ["env", "TERM=dumb", "NO_COLOR=1", root.cliPath, "attendance"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const clean = root.stripFormatting(text);
                root.attendanceResponseRejected = clean.indexOf("Maximum Fail Attempts Reached") >= 0
                    || clean.indexOf("Please login first") >= 0;
                const parsed = root.tableRows(text, 7);
                root.attendanceRows = parsed.map(parts => ({
                    subject: parts[1], type: parts[2], attended: parts[4],
                    percentage: parts[5], alert: parts[6]
                }));
                root.attendanceLoading = false;
                if (root.attendanceRows.length === 0) {
                    root.attendanceError = root.portalError(text, qsTr("No attendance records found"));
                    const clean = root.stripFormatting(text);
                    if (clean.indexOf("Maximum Fail Attempts Reached") >= 0 || clean.indexOf("Please login first") >= 0)
                        root.refreshChain = false;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    console.warn("CLI-TOP attendance:", root.stripFormatting(text).trim());
                    root.attendanceError = qsTr("Could not load attendance");
                }
            }
        }
        onExited: code => {
            root.attendanceLoading = false;
            if (code !== 0) {
                root.attendanceError = qsTr("CLI-TOP attendance request failed");
                root.refreshChain = false;
            } else if (root.attendanceResponseRejected) {
                root.attendanceRows = root.cacheData.attendance || [];
                root.refreshChain = false;
            } else if (root.refreshChain) {
                root.cacheData.attendance = root.attendanceRows;
                root.saveCache();
                root.refreshDa();
            } else {
                root.cacheData.attendance = root.attendanceRows;
                root.saveCache();
            }
        }
    }

    Process {
        id: daProcess
        command: ["sh", "-c", "printf 'exit\\n' | TERM=dumb NO_COLOR=1 \"$1\" da", "caelestia-cli-da", root.cliPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const clean = root.stripFormatting(text);
                root.daResponseRejected = clean.indexOf("Maximum Fail Attempts Reached") >= 0
                    || clean.indexOf("Please login first") >= 0;
                const parsed = root.tableRows(text, 4);
                root.daRows = root.sortAssignments(parsed.map(parts => ({
                    subject: parts[1], status: parts[2], deadline: parts[3]
                })));
                root.daLoading = false;
                if (root.daRows.length === 0)
                    root.daError = root.portalError(text, qsTr("No assignment records found"));
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    console.warn("CLI-TOP assignments:", root.stripFormatting(text).trim());
                    root.daError = qsTr("Could not load assignments");
                }
            }
        }
        onExited: code => {
            root.daLoading = false;
            if (code !== 0)
                root.daError = qsTr("CLI-TOP assignment request failed");
            else if (!root.daResponseRejected) {
                root.cacheData.assignments = root.daRows;
                root.saveCache();
                if (root.scheduleRows.length > 0 || root.attendanceRows.length > 0 || root.daRows.length > 0)
                    root.autoRefreshReady = true;
            } else {
                root.daRows = root.sortAssignments(root.cacheData.assignments || []);
            }
            root.refreshChain = false;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            Layout.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "school"
                fontStyle: Tokens.font.icon.extraLarge
                color: root.cPrimary
            }

            ColumnLayout {
                spacing: 0

                StyledText {
                    text: qsTr("College")
                    font: Tokens.font.title.large
                    color: root.cOnSurface
                }

                StyledText {
                    text: qsTr("CLI-TOP · automatic refresh every 30 minutes")
                    font: Tokens.font.body.small
                    color: root.cOnSurfaceVariant
                }
            }

            Item { Layout.fillWidth: true }

            StyledText {
                visible: root.scheduleLoading || root.attendanceLoading || root.daLoading
                text: qsTr("Updating…")
                font: Tokens.font.body.small
                color: root.cOnSurfaceVariant
            }

            IconButton {
                icon: "refresh"
                enabled: root.portalEnabled && !root.scheduleLoading && !root.attendanceLoading && !root.daLoading
                onClicked: root.refreshAll()
            }
        }

        StyledRect {
            Layout.fillWidth: true
            visible: !root.portalEnabled
            implicitHeight: disabledMessage.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3errorContainer

            StyledText {
                id: disabledMessage
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                text: qsTr("VTOP access is disabled. No login or data requests will be made.")
                font: Tokens.font.label.medium
                color: Colours.palette.m3onErrorContainer
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: 235
            radius: Tokens.rounding.large
            color: root.cSurface

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        spacing: 0

                        StyledText {
                            text: root.dayName()
                            font: Tokens.font.title.medium
                            color: root.cOnSurface
                        }

                        StyledText {
                            text: root.selectedDate() + (root.scheduleNote ? " · " + root.scheduleNote : "")
                            font: Tokens.font.body.small
                            color: root.cOnSurfaceVariant
                        }
                    }

                    Item { Layout.fillWidth: true }

                    IconButton {
                        icon: "chevron_left"
                        enabled: root.dayOffset > 0 && !root.scheduleLoading
                        onClicked: root.moveDay(-1)
                    }

                    IconButton {
                        icon: "today"
                        enabled: root.dayOffset !== 0 && !root.scheduleLoading
                        onClicked: {
                            root.dayOffset = 0;
                            root.scheduleRows = [];
                            root.refreshSchedule();
                        }
                    }

                    IconButton {
                        icon: "chevron_right"
                        enabled: root.dayOffset < 2 && !root.scheduleLoading
                        onClicked: root.moveDay(1)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.scheduleLoading || root.scheduleError !== "" || (root.isWeekend() && root.scheduleRows.length === 0)
                    text: root.scheduleLoading ? qsTr("Loading timetable…") : root.scheduleError !== "" ? root.scheduleError : qsTr("No classes on Saturday or Sunday")
                    color: root.scheduleError !== "" ? root.cError : root.cOnSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                }

                ListView {
                    id: scheduleList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Tokens.spacing.extraSmall
                    model: root.scheduleRows
                    ScrollBar.vertical: StyledScrollBar { flickable: scheduleList }

                    delegate: StyledRect {
                        id: scheduleRow
                        required property var modelData
                        width: ListView.view.width
                        implicitHeight: 38
                        radius: Tokens.rounding.small
                        color: root.cSurfaceHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            StyledText {
                                Layout.preferredWidth: 92
                                text: scheduleRow.modelData.time
                                font: Tokens.font.mono.small
                                color: root.cPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: scheduleRow.modelData.subject
                                font: Tokens.font.label.medium
                                color: root.cOnSurface
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.preferredWidth: 65
                                text: scheduleRow.modelData.venue
                                font: Tokens.font.body.small
                                color: root.cOnSurfaceVariant
                            }

                            StyledText {
                                Layout.preferredWidth: 38
                                text: scheduleRow.modelData.percentage
                                font: Tokens.font.label.medium
                                color: root.percentageColour(scheduleRow.modelData.percentage)
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.medium

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 3
                radius: Tokens.rounding.large
                color: root.cSurface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true

                        MaterialIcon {
                            text: "fact_check"
                            fontStyle: Tokens.font.icon.medium
                            color: root.cSecondary
                        }

                        StyledText {
                            text: qsTr("Attendance")
                            font: Tokens.font.title.medium
                            color: root.cOnSurface
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            text: qsTr("%1 records").arg(root.attendanceRows.length)
                            font: Tokens.font.body.small
                            color: root.cOnSurfaceVariant
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.attendanceLoading || root.attendanceError !== ""
                        text: root.attendanceLoading ? qsTr("Loading attendance…") : root.attendanceError
                        color: root.attendanceError !== "" ? root.cError : root.cOnSurfaceVariant
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ListView {
                        id: attendanceList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Tokens.spacing.extraSmall
                        model: root.attendanceRows
                        ScrollBar.vertical: StyledScrollBar { flickable: attendanceList }

                        delegate: StyledRect {
                            id: attendanceRow
                            required property var modelData
                            width: ListView.view.width
                            implicitHeight: 62
                            radius: Tokens.rounding.small
                            color: root.cSurfaceHigh

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.padding.small
                                anchors.rightMargin: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: attendanceRow.modelData.subject
                                        font: Tokens.font.label.medium
                                        color: root.cOnSurface
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: attendanceRow.modelData.type + " · " + attendanceRow.modelData.attended
                                        font: Tokens.font.body.small
                                        color: root.cOnSurfaceVariant
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: attendanceRow.modelData.alert
                                        font: Tokens.font.label.small
                                        color: root.percentageColour(attendanceRow.modelData.percentage)
                                        elide: Text.ElideRight
                                    }
                                }

                                StyledText {
                                    text: attendanceRow.modelData.percentage
                                    font: Tokens.font.title.small
                                    color: root.percentageColour(attendanceRow.modelData.percentage)
                                }
                            }
                        }
                    }
                }
            }

            StyledRect {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 2
                radius: Tokens.rounding.large
                color: root.cSurface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    spacing: Tokens.spacing.small

                    RowLayout {
                        Layout.fillWidth: true

                        MaterialIcon {
                            text: "assignment"
                            fontStyle: Tokens.font.icon.medium
                            color: root.cTertiary
                        }

                        StyledText {
                            text: qsTr("Digital assignments")
                            font: Tokens.font.title.medium
                            color: root.cOnSurface
                        }

                        Item { Layout.fillWidth: true }

                        StyledText {
                            text: qsTr("Next deadlines")
                            font: Tokens.font.body.small
                            color: root.cOnSurfaceVariant
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.daLoading || root.daError !== ""
                        text: root.daLoading ? qsTr("Loading assignments…") : root.daError
                        color: root.daError !== "" ? root.cError : root.cOnSurfaceVariant
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ListView {
                        id: daList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Tokens.spacing.extraSmall
                        model: root.daRows
                        ScrollBar.vertical: StyledScrollBar { flickable: daList }

                        delegate: StyledRect {
                            id: daRow
                            required property var modelData
                            readonly property bool dueToday: root.isDeadlineToday(modelData.deadline)
                            width: ListView.view.width
                            implicitHeight: 48
                            radius: Tokens.rounding.small
                            color: dueToday ? Qt.alpha(root.cError, 0.14) : root.cSurfaceHigh
                            border.width: dueToday ? 2 : 0
                            border.color: dueToday ? root.cError : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.padding.small
                                anchors.rightMargin: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: daRow.modelData.subject
                                        font: Tokens.font.label.medium
                                        color: root.cOnSurface
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        text: daRow.modelData.deadline === "N/A"
                                            ? qsTr("No pending deadline")
                                            : daRow.dueToday
                                                ? qsTr("Due today · %1").arg(daRow.modelData.deadline)
                                                : qsTr("Due %1").arg(daRow.modelData.deadline)
                                        font: Tokens.font.body.small
                                        color: daRow.modelData.deadline === "N/A"
                                            ? root.cOnSurfaceVariant
                                            : daRow.dueToday ? root.cError : root.cTertiary
                                    }
                                }

                                StyledRect {
                                    implicitWidth: statusText.implicitWidth + Tokens.padding.small * 2
                                    implicitHeight: 28
                                    radius: Tokens.rounding.full
                                    color: Colours.tPalette.m3tertiaryContainer

                                    StyledText {
                                        id: statusText
                                        anchors.centerIn: parent
                                        text: daRow.modelData.status
                                        font: Tokens.font.label.small
                                        color: Colours.palette.m3onTertiaryContainer
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
