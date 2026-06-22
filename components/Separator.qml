import QtQuick

Rectangle {
    required property int separatorHeight
    required property string separatorColor

    width: 1
    height: separatorHeight

    color: separatorColor

    opacity: 0.5
}
