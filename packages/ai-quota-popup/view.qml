import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: popup
    width: 440
    height: 660
    minimumWidth: 350
    minimumHeight: 360
    visible: false
    color: "#171918"
    title: "Quota details"
    flags: Qt.Tool | Qt.FramelessWindowHint

    readonly property color surface: "#222524"
    readonly property color raised: "#2d3130"
    readonly property color ink: "#f2f3f0"
    readonly property color muted: "#aab2ad"
    readonly property color accent: "#199e70"
    property var snapshot: JSON.parse(bridge.payload)

    onClosing: function(close) {
        close.accepted = false
        bridge.hide()
    }
    Keys.onEscapePressed: bridge.hide()

    Rectangle {
        anchors.fill: parent
        color: popup.color
        border.width: 1
        border.color: "#3b403d"
        radius: 16
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    textFormat: Text.PlainText
                    text: "QUOTA / DETAILS"
                    color: popup.muted
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 1.5
                }
                Text {
                    textFormat: Text.PlainText
                    text: snapshot.stale ? "Last known snapshot" : "Subscription windows"
                    color: popup.ink
                    font.pixelSize: 21
                    font.weight: Font.DemiBold
                }
            }
            Button {
                id: reload
                text: "↻"
                Accessible.name: "Refresh quota"
                onClicked: bridge.refresh()
                background: Rectangle { color: reload.hovered ? popup.raised : popup.surface; radius: 12 }
                contentItem: Text {
                    textFormat: Text.PlainText
                    text: reload.text
                    color: popup.ink
                    font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Button {
                id: closeButton
                text: "×"
                Accessible.name: "Close quota details"
                onClicked: bridge.hide()
                background: Rectangle { color: closeButton.hovered ? popup.raised : popup.surface; radius: 12 }
                contentItem: Text {
                    textFormat: Text.PlainText
                    text: closeButton.text
                    color: popup.ink
                    font.pixelSize: 22
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: snapshot.stale || snapshot.error || snapshot.loading
            text: snapshot.stale
                ? snapshot.error + " · showing data from " + snapshot.loadedAt
                : snapshot.error || "Updating…"
            color: snapshot.stale || snapshot.error ? "#f0ba78" : popup.muted
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        ScrollView {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            contentWidth: availableWidth

            Column {
                width: scroller.availableWidth
                spacing: 12

                Repeater {
                    model: snapshot.cards
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        property var provider: modelData
                        width: parent.width
                        height: body.implicitHeight + 36
                        radius: 18
                        color: popup.surface
                        border.width: provider.id === snapshot.selected ? 1 : 0
                        border.color: popup.accent

                        Column {
                            id: body
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18
                            spacing: 17

                            RowLayout {
                                width: parent.width
                                spacing: 10
                                Rectangle {
                                    width: 36
                                    height: 36
                                    radius: 10
                                    color: popup.raised
                                    Image {
                                        anchors.centerIn: parent
                                        width: 24
                                        height: 24
                                        source: card.provider.logo
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        textFormat: Text.PlainText
                                        text: card.provider.title
                                        color: popup.ink
                                        font.pixelSize: 18
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        text: card.provider.accounts.length + (card.provider.accounts.length === 1 ? " account" : " accounts")
                                        color: popup.muted
                                        font.pixelSize: 12
                                    }
                                }
                                ColumnLayout {
                                    spacing: 1
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.alignment: Qt.AlignRight
                                        text: card.provider.remaining === null ? "—" : Math.round(card.provider.remaining) + "%"
                                        color: popup.ink
                                        font.pixelSize: 29
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        Layout.alignment: Qt.AlignRight
                                        text: "remaining"
                                        color: popup.muted
                                        font.pixelSize: 11
                                    }
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                visible: card.provider.state === "error" || card.provider.accounts.length === 0
                                text: card.provider.accounts.length ? "No usable coding quota" : "No accounts available"
                                color: "#f0ba78"
                                font.pixelSize: 12
                            }

                            Repeater {
                                model: card.provider.accounts
                                delegate: Column {
                                    required property var modelData
                                    property var account: modelData
                                    width: body.width
                                    spacing: 12

                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: "#3b403d"
                                    }
                                    RowLayout {
                                        width: parent.width
                                        Text {
                                            textFormat: Text.PlainText
                                            Layout.fillWidth: true
                                            text: account.name
                                            color: popup.ink
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            textFormat: Text.PlainText
                                            text: account.plan
                                            color: popup.muted
                                            font.pixelSize: 12
                                        }
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        visible: account.error !== ""
                                        text: "Unavailable · " + account.error
                                        color: "#f0ba78"
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        font.pixelSize: 12
                                    }
                                    Repeater {
                                        model: account.meters
                                        delegate: Column {
                                            required property var modelData
                                            property var meter: modelData
                                            width: parent.width
                                            spacing: 7

                                            RowLayout {
                                                width: parent.width
                                                Text {
                                                    textFormat: Text.PlainText
                                                    Layout.fillWidth: true
                                                    text: meter.label
                                                    color: popup.ink
                                                    font.pixelSize: 13
                                                    font.weight: Font.Medium
                                                }
                                                Text {
                                                    textFormat: Text.PlainText
                                                    text: meter.reset
                                                    color: popup.muted
                                                    font.pixelSize: 11
                                                }
                                            }
                                            RowLayout {
                                                width: parent.width
                                                spacing: 10
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    height: 7
                                                    radius: 4
                                                    color: popup.raised
                                                    Rectangle {
                                                        width: parent.width * Math.max(0, (meter.remaining || 0) / 100)
                                                        height: parent.height
                                                        radius: 4
                                                        color: popup.accent
                                                    }
                                                }
                                                Text {
                                                    textFormat: Text.PlainText
                                                    text: meter.remaining === null ? "—" : meter.remaining + "% left"
                                                    color: popup.ink
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                            Item {
                                                visible: meter.timed
                                                width: parent.width
                                                height: visible ? 31 : 0
                                                Rectangle {
                                                    width: parent.width
                                                    height: 1
                                                    y: 6
                                                    color: "#59615b"
                                                }
                                                Rectangle {
                                                    id: nowMarker
                                                    x: Math.max(0, Math.min(parent.width - width, meter.timeFraction * parent.width - width / 2))
                                                    y: 1
                                                    width: 2
                                                    height: 11
                                                    color: popup.ink
                                                }
                                                Text {
                                                    textFormat: Text.PlainText
                                                    anchors.left: parent.left
                                                    anchors.bottom: parent.bottom
                                                    text: meter.startLabel
                                                    color: popup.muted
                                                    font.pixelSize: 10
                                                }
                                                Text {
                                                    textFormat: Text.PlainText
                                                    x: Math.max(72, Math.min(parent.width - width - 72, nowMarker.x - width / 2))
                                                    anchors.bottom: parent.bottom
                                                    text: "NOW"
                                                    color: popup.muted
                                                    font.pixelSize: 10
                                                }
                                                Text {
                                                    textFormat: Text.PlainText
                                                    anchors.right: parent.right
                                                    anchors.bottom: parent.bottom
                                                    text: meter.endLabel
                                                    color: popup.muted
                                                    font.pixelSize: 10
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    textFormat: Text.PlainText
                    visible: snapshot.cards.length === 0
                    width: parent.width
                    text: snapshot.loading ? "Loading subscription windows…" : (snapshot.error || "No providers available")
                    color: popup.muted
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font.pixelSize: 14
                    topPadding: 32
                }
            }
        }
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: snapshot.loadedAt ? "Updated " + snapshot.loadedAt : ""
            color: popup.muted
            font.pixelSize: 11
        }
    }
}
