pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    required property string itemName
    required property string itemPath
    required property string itemType
    required property string itemIcon
    property bool isDesktopFile: false
    property bool isSelected: false
    property bool isHovered: false

    readonly property string thumbnailPath: {
        const ext = itemPath.substring(itemPath.lastIndexOf('.') + 1).toLowerCase();
        const videoExts = ['mp4', 'webm', 'mov', 'avi', 'mkv', 'gif'];
        const imageExts = ['jpg', 'jpeg', 'png', 'webp', 'tif', 'tiff', 'bmp'];

        if (itemType === 'folder' || isDesktopFile) {
            return '';
        }

        if (videoExts.includes(ext) || imageExts.includes(ext)) {
            const fileName = itemPath.substring(itemPath.lastIndexOf('/') + 1);
            const home = Quickshell.env("HOME") || "/home/verse";
            return home + "/.cache/quickshell/desktop_thumbnails/" + fileName + ".jpg";
        }

        return '';
    }

    readonly property bool hasThumbnail: thumbnailPath !== ''
    property int thumbnailRefresh: 0

    FileView {
        path: root.thumbnailPath
        watchChanges: root.hasThumbnail

        onFileChanged: {
            root.thumbnailRefresh++;
        }
    }

    // background on hover and active selection
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: {
            if (root.isSelected)
                return root.isHovered ? "#58ffffff" : "#44ffffff";
            if (root.isHovered)
                return "#20ffffff";
            return "transparent";
        }
        border.color: {
            if (root.isSelected)
                return root.isHovered ? "#90ffffff" : "#70ffffff";
            if (root.isHovered)
                return "#30ffffff";
            return "transparent";
        }
        border.width: 1
        visible: root.isSelected || root.isHovered

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
        Behavior on border.color {
            ColorAnimation { duration: 120 }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4

        // icon or thumbnail container
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Config.desktop.iconSize
            Layout.preferredHeight: Config.desktop.iconSize

            Loader {
                id: iconLoader
                anchors.centerIn: parent
                width: Config.desktop.iconSize
                height: Config.desktop.iconSize
                sourceComponent: root.hasThumbnail ? thumbnailComponent : standardIconComponent
            }
        }

        // label container
        Item {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: labelText.implicitHeight + 6

            Text {
                id: labelText
                anchors.centerIn: parent
                width: parent.width
                text: root.itemName
                color: "#ffffff"
                font.family: Config.defaultFont
                font.pixelSize: Styling.fontSize(0)
                font.weight: root.isSelected ? Font.DemiBold : Font.Normal
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                style: Text.Outline
                styleColor: "#80000000"
            }
        }
    }

    Component {
        id: thumbnailComponent

        Image {
            id: thumbImg
            source: {
                root.thumbnailRefresh;
                return "file://" + root.thumbnailPath;
            }
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            cache: false

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: "#30ffffff"
                border.width: 1
                radius: 6
            }

            Loader {
                anchors.fill: parent
                active: thumbImg.status === Image.Error
                sourceComponent: standardIconComponent
            }
        }
    }

    Component {
        id: standardIconComponent

        Item {
            id: fallbackContainer

            Image {
                id: sysIcon
                anchors.fill: parent
                source: {
                    if (root.itemType === "folder") {
                        let lower = root.itemName.toLowerCase();
                        if (lower === "downloads" || lower === "download") return "image://icon/folder-download";
                        if (lower === "documents" || lower === "document") return "image://icon/folder-documents";
                        if (lower === "pictures" || lower === "photos" || lower === "images") return "image://icon/folder-pictures";
                        if (lower === "music" || lower === "songs") return "image://icon/folder-music";
                        if (lower === "videos" || lower === "video" || lower === "movies") return "image://icon/folder-videos";
                        return "image://icon/folder";
                    }
                    return "image://icon/" + root.itemIcon;
                }
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: sysIcon.status !== Image.Ready
                text: {
                    if (root.itemType === "folder") {
                        return Icons.folder;
                    } else if (root.isDesktopFile) {
                        return Icons.apps;
                    }
                    return Icons.file;
                }
                font.family: Icons.font
                font.pixelSize: Config.desktop.iconSize * 0.85
                color: root.itemType === "folder" ? "#42a5f5" : "#ffffff"
            }
        }
    }
}
