import QtQuick
import QtQuick.Controls
import Omarchy.Controls

Item {
    id: root
    width: 40
    height: 40

    property bool isStrataActive: true
    property var activeModelName: "Strata (Qwen)"

    Rectangle {
        anchors.fill: parent
        color: isStrataActive ? "#7c4dff" : "#ff4081" // Purple for Strata, Pink for Gemma 4
        radius: 20
        
        Text {
            anchors.centerIn: parent
            text: isStrataActive ? "Q" : "G"
            color: "white"
            font.bold: true
            font.pixelSize: 18
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            isStrataActive = !isStrataActive
            activeModelName = isStrataActive ? "Strata (Qwen)" : "LM Studio (Gemma 4)"
            // Trigger the logic switch
            Model.swapModel(isStrataActive)
        }
    }
}