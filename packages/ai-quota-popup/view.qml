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
    property var snapshot: JSON.parse(bridge.payload)

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
    }
}
