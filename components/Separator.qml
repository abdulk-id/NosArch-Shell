import QtQuick

Rectangle {
    required property int separatorHeight
    required property string separatorColor

    anchors.verticalCenter: parent.verticalCenter
    width: 1
    height: separatorHeight

    color: separatorColor

    opacity: 0.5
}
