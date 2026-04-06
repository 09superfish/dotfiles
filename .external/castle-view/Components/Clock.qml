import QtQuick 2.15
import SddmComponents 2.0

Clock {
  id: time
  color: "#CDD6F4"
  timeFont.family: config.Font
  dateFont.family: config.Font
  anchors {
    topMargin: 10
    rightMargin: 120
    top: parent.top
    right: parent.right
  }
}
