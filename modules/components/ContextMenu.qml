import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

PanelWindow {
    id: contextWindow

    property var menuHandle: null
    property var customItems: []
    property int menuWidth: 160
    property int itemHeight: 32
    property string menuType: ""
    property int _pendingX: -1
    property int _pendingY: -1
    property bool _reopening: false
    property bool _closing: false

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    visible: false
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    exclusiveZone: 0

    mask: Region {
        item: menuContainer
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            menu.hoveredIndex = -1;
            menu.previousHoveredIndex = -1;
            contextWindow.close();
        }
    }

    Process {
        id: cursorPos
        running: false
        command: ["hyprctl", "cursorpos"]
        
        stdout: StdioCollector {
            onStreamFinished: {
                let coords = text.trim().split(",");
                if (coords.length === 2) {
                    contextWindow._pendingX = parseInt(coords[0].trim());
                    contextWindow._pendingY = parseInt(coords[1].trim());
                    Qt.callLater(contextWindow.tryOpenPendingMenu);
                }
            }
        }
    }

    function tryOpenPendingMenu() {
        if (!contextWindow.visible || contextWindow._pendingX < 0 || contextWindow._pendingY < 0)
            return;
        if (!menu.items || menu.items.length === 0)
            return;

        let margin = 8;
        let estHeight = menu.padding * 2;
        for (let i = 0; i < menu.items.length; i++) {
            estHeight += menu.items[i].isSeparator ? 10 : menu.itemHeight;
        }
        let maxW = Math.max(margin, contextWindow.width - menu.menuWidth - margin);
        let maxH = Math.max(margin, contextWindow.height - estHeight - margin);
        let clampedX = Math.max(margin, Math.min(contextWindow._pendingX, maxW));
        let clampedY = Math.max(margin, Math.min(contextWindow._pendingY, maxH));

        contextWindow._pendingX = -1;
        contextWindow._pendingY = -1;
        menu.popup(clampedX, clampedY);
    }

    Item {
        id: menuContainer
        anchors.fill: parent

        OptionsMenu {
            id: menu
            popupType: Popup.Item
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            onClosed: {
                if (!contextWindow._reopening && contextWindow.visible) {
                    contextWindow.close();
                }
            }
            onItemsChanged: {
                if (contextWindow.visible && !menu.visible && contextWindow._pendingX >= 0) {
                    Qt.callLater(contextWindow.tryOpenPendingMenu);
                }
            }

            menuWidth: contextWindow.menuWidth
            itemHeight: contextWindow.itemHeight

            function cleanMenuText(text) {
                if (!text || text === "") return "";
                
                text = String(text);
                
                if (text.startsWith(":/// ")) {
                    text = text.substring(5);
                }
                
                return text.trim();
            }

            function isValidIcon(icon) {
                if (!icon || icon === "") return false;
                
                if (icon.length > 4) return false;
                if (icon.includes("/") || icon.includes(".") || icon.includes(":")) return false;
                
                return true;
            }

            function isImageIcon(icon) {
                if (!icon || icon === "") return false;
                
                if (icon.includes("/") || icon.includes(".")) return true;
                if (icon.startsWith("file://") || icon.startsWith("http")) return true;
                if (icon.length > 10) return true;
                
                return false;
            }

            QsMenuOpener {
                id: menuOpener
                menu: contextWindow.menuHandle

                onChildrenChanged: {
                    console.log("Menu children changed, count:", children ? children.values.length : "null");
                }
            }

            items: {
                if (contextWindow.customItems && contextWindow.customItems.length > 0) {
                    console.log("Using custom items:", contextWindow.customItems.length);
                    return contextWindow.customItems.map(item => ({
                        text: item.text || "",
                        icon: item.icon || "",
                        isImageIcon: item.isImageIcon || false,
                        enabled: item.enabled !== false,
                        isSeparator: item.isSeparator || false,
                        highlightColor: item.highlightColor,
                        textColor: item.textColor,
                        onTriggered: function() {
                            let callback = item.onTriggered;
                            contextWindow.close();
                            if (callback) {
                                Qt.callLater(callback);
                            }
                        }
                    }));
                }

                if (!contextWindow.menuHandle) {
                    return [];
                }

                console.log("Building menu items from systray...");
                console.log("menuHandle:", contextWindow.menuHandle);
                console.log("menuOpener.children:", menuOpener.children);

                if (!menuOpener.children || !menuOpener.children.values) {
                    console.log("No children values available");
                    return [];
                }

                let menuItems = [];
                console.log("Children count:", menuOpener.children.values.length);

                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    let entry = menuOpener.children.values[i];
                    console.log("Entry", i, ":", entry, "isSeparator:", entry ? entry.isSeparator : "null", "text:", entry ? entry.text : "null", "icon:", entry ? entry.icon : "null");

                    if (entry) {
                        if (entry.isSeparator) {
                            menuItems.push({
                                text: "",
                                icon: "",
                                enabled: false,
                                isSeparator: true,
                                onTriggered: function () {}
                            });
                        } else {
                            let originalText = entry.text;
                            let cleanText = menu.cleanMenuText(originalText);
                            
                            let iconToUse = "";
                            let useImageIcon = false;
                            
                            if (entry.icon) {
                                if (menu.isValidIcon(entry.icon)) {
                                    iconToUse = entry.icon;
                                    useImageIcon = false;
                                } else if (menu.isImageIcon(entry.icon)) {
                                    // wrap theme icon names into image://icon/ so Qt Image can resolve them
                                    let ic = entry.icon;
                                    if (!ic.includes("/") && !ic.includes(".") && !ic.startsWith("http")) {
                                        ic = "image://icon/" + ic;
                                    }
                                    iconToUse = ic;
                                    useImageIcon = true;
                                }
                            }

                            if (originalText !== cleanText) {
                                console.log("Text cleaned - Original:", originalText, "-> Clean:", cleanText);
                            }
                            if (entry.icon) {
                                console.log("Icon processed - Original:", entry.icon, "-> Used:", iconToUse, "isImage:", useImageIcon);
                            }

                            if (cleanText === "" && iconToUse === "") {
                                console.log("Skipping entry with no valid text or icon:", originalText);
                                continue;
                            }

                            menuItems.push({
                                text: cleanText,
                                icon: iconToUse,
                                isImageIcon: useImageIcon,
                                enabled: entry.enabled !== false,
                                isSeparator: false,
                                onTriggered: function () {
                                    console.log("Triggering menu item:", cleanText);
                                    let callback = entry.triggered;
                                    contextWindow.close();
                                    if (callback) {
                                        Qt.callLater(callback);
                                    }
                                }
                            });
                        }
                    }
                }
                console.log("Final menu items count:", menuItems.length);
                return menuItems;
            }
        }
    }

    function openMenu(handle) {
        console.log("Opening context menu");
        _reopening = true;
        if (menu.visible) {
            menu.close();
        }
        _pendingX = -1;
        _pendingY = -1;
        menuHandle = handle;
        customItems = [];
        menuType = "";
        _reopening = false;
        visible = true;
        WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive;
        cursorPos.running = false;
        cursorPos.running = true;
    }

    function openCustomMenu(items, width, height, type) {
        console.log("Opening custom context menu with", items.length, "items");
        _reopening = true;
        if (menu.visible) {
            menu.close();
        }
        _pendingX = -1;
        _pendingY = -1;
        menuHandle = null;
        customItems = items;
        menuType = type || "";
        if (width !== undefined) menuWidth = width;
        if (height !== undefined) itemHeight = height;
        _reopening = false;
        visible = true;
        WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive;
        if (menuType === "player") {
            Visibilities.playerMenuOpen = true;
        }
        cursorPos.running = false;
        cursorPos.running = true;
    }

    function close() {
        if (_closing) return;
        _closing = true;
        console.log("Closing context menu");
        _pendingX = -1;
        _pendingY = -1;
        menu.hoveredIndex = -1;
        menu.previousHoveredIndex = -1;
        if (menu.visible) {
            menu.close();
        }
        visible = false;
        WlrLayershell.keyboardFocus = WlrKeyboardFocus.None;
        if (menuType === "player") {
            Visibilities.playerMenuOpen = false;
        }
        Qt.callLater(() => {
            menuHandle = null;
            customItems = [];
            menuType = "";
            _closing = false;
        });
    }

    onVisibleChanged: {
        if (!visible && !_closing) {
            close();
        }
    }

}
