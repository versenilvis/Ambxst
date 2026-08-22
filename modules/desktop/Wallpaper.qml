pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.config

PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell:wallpaper"
    exclusionMode: ExclusionMode.Ignore
    color: "black"

    readonly property string defaultWallpaper: decodeURIComponent(Qt.resolvedUrl("../../assets/wallpapers_example/05-ambxst-blobs-purple.png").toString().replace("file://", ""))

    FileView {
        id: wallpaperConfig
        path: Quickshell.dataPath("wallpapers.json")

        JsonAdapter {
            property string currentWall: ""
            property string wallPath: ""
        }
    }

    readonly property string wallpaperSource: {
        const customWall = wallpaperConfig.adapter.currentWall;
        if (customWall && customWall.length > 0) {
            return customWall;
        }
        return defaultWallpaper;
    }

    Image {
        id: wallImage
        anchors.fill: parent
        sourceSize.width: parent.width > 0 ? parent.width : 0
        sourceSize.height: parent.height > 0 ? parent.height : 0
        source: root.wallpaperSource ? "file://" + root.wallpaperSource : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        cache: false
    }
}
