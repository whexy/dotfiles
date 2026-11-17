import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: popup
    width: 360
    height: Math.min(content.implicitHeight + 2 * margin, Screen.desktopAvailableHeight - 60)
    visible: false
    color: "transparent"
    title: "Quota details"
    flags: Qt.Tool | Qt.FramelessWindowHint

    readonly property int margin: 8
    readonly property color surface: "#1d201e"
    readonly property color ink: "#ffffff"
    readonly property color secondary: Qt.rgba(0.92, 0.92, 0.96, 0.6)
    readonly property color green: "#29915c"
    readonly property color amber: "#c9661f"
    readonly property string mono: Qt.platform.os === "osx" ? "Menlo" : "monospace"
    // Usage series slots 0 to 8, the dark palette of the ai-quota website.
    readonly property var series: ["#8f8881", "#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#2f9a2f", "#9085e9", "#e66767"]
    property var snapshot: JSON.parse(bridge.payload)

    component Segmented: Rectangle {
        id: segmented
        property var options: []
        property string current: ""
        signal picked(string key)
        radius: height / 2
        color: "transparent"
        Row {
            anchors.fill: parent
            anchors.margins: 2
            Repeater {
                model: segmented.options
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: modelData.key === segmented.current
                    width: parent.width / segmented.options.length
                    height: parent.height
                    radius: height / 2
                    color: active ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: modelData.label
                        color: parent.active ? popup.ink : popup.secondary
                        font.pixelSize: 12
                        font.weight: parent.active ? Font.DemiBold : Font.Medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: segmented.picked(modelData.key)
                    }
                }
            }
        }
    }

    function tint(name) {
        return name === "amber" ? amber : name === "green" ? green : secondary
    }
    function percent(value) {
        return value === null || value === undefined ? "—" : Math.round(value) + "%"
    }
    function leaf(color) {
        return "data:image/svg+xml;utf8," + encodeURIComponent(
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" + color
            + "' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'>"
            + "<path d='M11 20A7 7 0 0 1 9.8 6.1C15.5 5 17 4.48 19 2c1 2 2 4.18 2 8 0 5.5-4.78 10-10 10Z'/>"
            + "<path d='M2 21c0-3 1.85-5.36 5.08-6C9.5 14.52 12 13 13 12'/></svg>")
    }

    onHeightChanged: bridge.place()
    onClosing: function(close) {
        close.accepted = false
        bridge.hide()
    }
    Shortcut {
        sequence: "Escape"
        onActivated: bridge.hide()
    }

    ScrollView {
        id: scroller
        anchors.fill: parent
        anchors.margins: popup.margin
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        contentWidth: availableWidth

        Column {
            id: content
            width: scroller.availableWidth
            spacing: 12

            Rectangle {
                width: content.width
                height: 38
                radius: 19
                color: popup.surface
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.055)
                Segmented {
                    anchors.fill: parent
                    anchors.margins: 4
                    options: [{ key: "quota", label: "Quota" }, { key: "usage", label: "Usage" }]
                    current: snapshot.view
                    onPicked: function(key) { bridge.setView(key) }
                }
            }

            Column {
                id: quotaView
                visible: snapshot.view === "quota"
                width: content.width
                spacing: 12

                Repeater {
                    model: snapshot.cards
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        property var account: modelData
                        width: content.width
                        height: body.implicitHeight + 40
                        radius: 23
                        color: popup.surface
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.055)

                        Column {
                            id: body
                            x: 20
                            y: 20
                            width: parent.width - 40
                            spacing: 19

                            RowLayout {
                                width: parent.width
                                spacing: 11
                                Rectangle {
                                    Layout.preferredWidth: 34
                                    Layout.preferredHeight: 34
                                    radius: 10
                                    color: Qt.rgba(1, 1, 1, 0.055)
                                    Image {
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        sourceSize: Qt.size(36, 36)
                                        source: card.account.logo
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        textFormat: Text.PlainText
                                        text: card.account.title
                                        color: popup.ink
                                        font.pixelSize: 17
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: card.account.plan
                                        color: popup.secondary
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    text: popup.percent(card.account.headline)
                                    color: popup.ink
                                    font.pixelSize: 29
                                    font.weight: Font.Medium
                                    font.features: ({ "tnum": 1 })
                                }
                            }

                            Repeater {
                                model: card.account.meters
                                delegate: Column {
                                    id: timeline
                                    required property var modelData
                                    property var meter: modelData
                                    readonly property color tint: popup.tint(meter.tint)
                                    width: body.width
                                    spacing: 10

                                    RowLayout {
                                        width: parent.width
                                        Text {
                                            Layout.fillWidth: true
                                            textFormat: Text.PlainText
                                            text: timeline.meter.label
                                            color: popup.ink
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: timeline.meter.countdown
                                            color: popup.secondary
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            font.family: popup.mono
                                        }
                                    }

                                    Item {
                                        id: track
                                        readonly property real usageX: width * timeline.meter.fraction
                                        readonly property real badgeWidth: 46
                                        readonly property real badgeX: Math.min(Math.max(usageX, badgeWidth / 2), Math.max(badgeWidth / 2, width - badgeWidth / 2))
                                        readonly property bool showNow: timeline.meter.elapsed !== null
                                        readonly property bool showProjection: timeline.meter.projection !== null && timeline.meter.projection > timeline.meter.used
                                        readonly property real projectionX: showProjection ? width * timeline.meter.projectionFraction : 0
                                        width: parent.width
                                        height: timeline.meter.axis.length ? 47 : 27

                                        Rectangle {
                                            y: 10
                                            width: parent.width
                                            height: 6
                                            radius: 3
                                            color: Qt.rgba(1, 1, 1, 0.08)
                                        }
                                        Rectangle {
                                            visible: track.showNow
                                            y: 10
                                            width: parent.width * (timeline.meter.elapsed || 0)
                                            height: 6
                                            radius: 3
                                            color: Qt.rgba(1, 1, 1, 0.045)
                                        }
                                        Repeater {
                                            model: track.showProjection ? Math.max(0, Math.floor((track.projectionX - track.usageX) / 6)) : 0
                                            delegate: Rectangle {
                                                required property int index
                                                x: track.usageX + index * 6
                                                y: 12
                                                width: 3
                                                height: 2
                                                color: timeline.tint
                                                opacity: 0.65
                                            }
                                        }
                                        Rectangle {
                                            visible: track.showProjection
                                            x: Math.min(track.width - 7, Math.max(0, track.projectionX - 3.5))
                                            y: 9.5
                                            width: 7
                                            height: 7
                                            radius: 3.5
                                            color: "transparent"
                                            border.width: 1.5
                                            border.color: timeline.tint
                                        }
                                        Rectangle {
                                            y: 10
                                            width: Math.max(0, track.usageX)
                                            height: 6
                                            radius: 3
                                            color: timeline.tint
                                        }
                                        Rectangle {
                                            visible: track.showNow
                                            x: Math.min(track.width - 2, track.width * (timeline.meter.elapsed || 0))
                                            y: 1
                                            width: 2
                                            height: 24
                                            color: popup.ink
                                        }
                                        Rectangle {
                                            x: track.badgeX - track.badgeWidth / 2
                                            y: 1
                                            width: track.badgeWidth
                                            height: 24
                                            radius: 12
                                            color: timeline.tint
                                            Text {
                                                anchors.centerIn: parent
                                                textFormat: Text.PlainText
                                                text: popup.percent(timeline.meter.used)
                                                color: "white"
                                                font.pixelSize: 12
                                                font.bold: true
                                                font.features: ({ "tnum": 1 })
                                            }
                                        }
                                        Repeater {
                                            model: timeline.meter.axis
                                            delegate: Item {
                                                required property var modelData
                                                readonly property real tickX: track.width * modelData.fraction
                                                Rectangle {
                                                    x: Math.min(track.width - 1, parent.tickX)
                                                    y: 25
                                                    width: 1
                                                    height: 4
                                                    color: Qt.rgba(1, 1, 1, 0.10)
                                                }
                                                Text {
                                                    x: Math.min(Math.max(0, parent.tickX - 18), Math.max(0, track.width - 36))
                                                    y: 33
                                                    width: 36
                                                    horizontalAlignment: Text.AlignHCenter
                                                    textFormat: Text.PlainText
                                                    text: modelData.label
                                                    color: popup.secondary
                                                    font.pixelSize: 8
                                                    font.weight: Font.Medium
                                                    font.family: popup.mono
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                visible: card.account.error !== ""
                                width: parent.width
                                spacing: 5
                                Text {
                                    textFormat: Text.PlainText
                                    text: "⚠"
                                    color: popup.amber
                                    font.pixelSize: 12
                                }
                                Text {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: card.account.error
                                    color: popup.amber
                                    font.pixelSize: 12
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Item {
                                visible: card.account.error === "" && card.account.forecast !== null
                                width: parent.width
                                height: forecastRow.implicitHeight + 3
                                RowLayout {
                                    id: forecastRow
                                    readonly property var forecast: card.account.forecast || { text: "", value: "", tint: "" }
                                    readonly property color tint: popup.tint(forecast.tint)
                                    y: 3
                                    width: parent.width
                                    spacing: 5
                                    Text {
                                        visible: forecastRow.forecast.tint === "amber"
                                        textFormat: Text.PlainText
                                        text: "↗"
                                        color: forecastRow.tint
                                        font.pixelSize: 11
                                    }
                                    Image {
                                        visible: forecastRow.forecast.tint === "green"
                                        Layout.preferredWidth: 11
                                        Layout.preferredHeight: 11
                                        sourceSize: Qt.size(22, 22)
                                        source: popup.leaf(forecastRow.tint.toString())
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: forecastRow.forecast.text
                                        color: forecastRow.tint
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: forecastRow.forecast.value
                                        color: forecastRow.tint
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: snapshot.cards.length === 0
                    width: content.width
                    height: 120
                    radius: 23
                    color: popup.surface
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.055)
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 40
                        textFormat: Text.PlainText
                        text: snapshot.loading ? "Fetching your quotas…" : (snapshot.error || "No quota for this provider")
                        color: popup.secondary
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.pixelSize: 13
                    }
                }

                Text {
                    visible: snapshot.cards.length > 0 && (snapshot.stale || snapshot.error !== "")
                    width: content.width
                    leftPadding: 12
                    textFormat: Text.PlainText
                    text: snapshot.error + (snapshot.loadedAt ? " · showing data from " + snapshot.loadedAt : "")
                    color: popup.amber
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                id: usageCard
                readonly property var usage: snapshot.usage
                visible: snapshot.view === "usage"
                width: content.width
                height: usageBody.implicitHeight + 40
                radius: 23
                color: popup.surface
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.055)

                Column {
                    id: usageBody
                    x: 20
                    y: 20
                    width: parent.width - 40
                    spacing: 18

                    RowLayout {
                        width: parent.width
                        spacing: 11
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                textFormat: Text.PlainText
                                text: "Usage"
                                color: popup.ink
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: usageCard.usage ? usageCard.usage.period : "All providers"
                                color: popup.secondary
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                        Segmented {
                            Layout.preferredWidth: 4 + 38 * snapshot.ranges.length
                            Layout.preferredHeight: 26
                            color: Qt.rgba(1, 1, 1, 0.055)
                            options: snapshot.ranges.map(function(key) { return { key: key, label: key } })
                            current: snapshot.range
                            onPicked: function(key) { bridge.setRange(key) }
                        }
                    }

                    Text {
                        visible: !usageCard.usage
                        width: parent.width
                        height: 72
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        text: snapshot.usageLoading ? "Fetching usage…" : (snapshot.usageError || "No usage yet")
                        color: popup.secondary
                        wrapMode: Text.WordWrap
                        font.pixelSize: 13
                    }

                    Column {
                        visible: !!usageCard.usage
                        width: parent.width
                        spacing: 4
                        RowLayout {
                            width: parent.width
                            spacing: 6
                            Text {
                                id: processedText
                                textFormat: Text.PlainText
                                text: usageCard.usage ? usageCard.usage.processed : ""
                                color: popup.ink
                                font.pixelSize: 29
                                font.weight: Font.Medium
                                font.features: ({ "tnum": 1 })
                            }
                            Text {
                                Layout.alignment: Qt.AlignBaseline
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: "tokens"
                                color: popup.secondary
                                font.pixelSize: 11
                            }
                            Text {
                                Layout.alignment: Qt.AlignBaseline
                                visible: text !== ""
                                textFormat: Text.PlainText
                                text: usageCard.usage ? usageCard.usage.cost : ""
                                color: popup.ink
                                font.pixelSize: 17
                                font.weight: Font.Medium
                                font.features: ({ "tnum": 1 })
                            }
                        }
                        Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: usageCard.usage ? usageCard.usage.activity : ""
                            color: popup.secondary
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    Column {
                        id: chart
                        readonly property var bars: usageCard.usage ? usageCard.usage.bars : []
                        property int hovered: -1
                        visible: bars.length > 0
                        width: parent.width
                        spacing: 10

                        Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: chart.hovered >= 0 && chart.hovered < chart.bars.length
                                ? chart.bars[chart.hovered].readout
                                : (usageCard.usage ? usageCard.usage.chartTitle : "")
                            color: popup.ink
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Item {
                            id: plot
                            readonly property real gutter: 30
                            readonly property real plotHeight: 64
                            readonly property real plotWidth: width - gutter
                            readonly property real gap: chart.bars.length > 40 ? 1 : 2
                            readonly property real step: chart.bars.length ? (plotWidth + gap) / chart.bars.length : 0
                            width: parent.width
                            height: plotHeight + 20

                            Repeater {
                                model: [
                                    { y: 0, label: usageCard.usage ? usageCard.usage.peak : "" },
                                    { y: 0.5, label: usageCard.usage ? usageCard.usage.half : "" },
                                    { y: 1, label: "0" }
                                ]
                                delegate: Item {
                                    required property var modelData
                                    Rectangle {
                                        x: plot.gutter
                                        y: plot.plotHeight * modelData.y - (modelData.y === 1 ? 1 : 0)
                                        width: plot.plotWidth
                                        height: 1
                                        color: Qt.rgba(1, 1, 1, modelData.y === 1 ? 0.10 : 0.05)
                                    }
                                    Text {
                                        y: plot.plotHeight * modelData.y - height / 2
                                        width: plot.gutter - 6
                                        horizontalAlignment: Text.AlignRight
                                        textFormat: Text.PlainText
                                        text: modelData.label
                                        color: popup.secondary
                                        font.pixelSize: 8
                                        font.weight: Font.Medium
                                        font.family: popup.mono
                                    }
                                }
                            }

                            Repeater {
                                model: chart.bars
                                delegate: Column {
                                    required property var modelData
                                    required property int index
                                    x: plot.gutter + index * plot.step
                                    y: plot.plotHeight - implicitHeight
                                    width: Math.max(1, plot.step - plot.gap)
                                    opacity: chart.hovered < 0 || chart.hovered === index ? 1 : 0.4
                                    Repeater {
                                        model: modelData.segments
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: parent.width
                                            height: plot.plotHeight * modelData.fraction
                                            color: popup.series[modelData.color] || popup.series[0]
                                        }
                                    }
                                }
                            }

                            Repeater {
                                model: usageCard.usage ? usageCard.usage.ticks : []
                                delegate: Text {
                                    required property var modelData
                                    readonly property real center: plot.gutter + (modelData.index + 0.5) * plot.step - plot.gap / 2
                                    x: Math.min(Math.max(plot.gutter, center - width / 2), plot.width - width)
                                    y: plot.plotHeight + 7
                                    width: 40
                                    horizontalAlignment: Text.AlignHCenter
                                    textFormat: Text.PlainText
                                    text: modelData.label
                                    color: popup.secondary
                                    font.pixelSize: 8
                                    font.weight: Font.Medium
                                    font.family: popup.mono
                                }
                            }

                            MouseArea {
                                x: plot.gutter
                                width: plot.plotWidth
                                height: plot.plotHeight
                                hoverEnabled: true
                                onPositionChanged: function(mouse) {
                                    chart.hovered = Math.min(chart.bars.length - 1, Math.floor(mouse.x / plot.step))
                                }
                                onExited: chart.hovered = -1
                            }
                        }
                    }

                    Column {
                        visible: !!usageCard.usage && usageCard.usage.groups.length > 0
                        width: parent.width
                        spacing: 12
                        Repeater {
                            model: usageCard.usage ? usageCard.usage.groups : []
                            delegate: Column {
                                id: group
                                required property var modelData
                                readonly property color tint: popup.series[modelData.color] || popup.series[0]
                                width: parent.width
                                spacing: 5
                                RowLayout {
                                    width: parent.width
                                    spacing: 8
                                    Rectangle {
                                        Layout.preferredWidth: 8
                                        Layout.preferredHeight: 8
                                        radius: 4
                                        color: group.tint
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: group.modelData.label
                                        color: popup.ink
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: group.modelData.detail
                                        color: popup.secondary
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: group.modelData.tokens
                                        color: popup.ink
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        font.features: ({ "tnum": 1 })
                                    }
                                }
                                Item {
                                    x: 16
                                    width: parent.width - 16
                                    height: 3
                                    Rectangle {
                                        width: parent.width
                                        height: 3
                                        radius: 1.5
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                    }
                                    Rectangle {
                                        width: Math.max(group.modelData.fraction > 0 ? 3 : 0, parent.width * group.modelData.fraction)
                                        height: 3
                                        radius: 1.5
                                        color: group.tint
                                    }
                                }
                                Text {
                                    x: 16
                                    width: parent.width - 16
                                    textFormat: Text.PlainText
                                    text: group.modelData.summary
                                    color: popup.secondary
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    font.features: ({ "tnum": 1 })
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Text {
                        visible: !!usageCard.usage && snapshot.usageError !== ""
                        width: parent.width
                        textFormat: Text.PlainText
                        text: snapshot.usageError + ", showing the last answer"
                        color: popup.amber
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
