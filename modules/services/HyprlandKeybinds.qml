import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config
import qs.modules.globals

QtObject {
    id: root

    property real lastApplyTime: 0.0

    property Process hyprctlProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    console.log("hyprctl stdout: " + text.trim())
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    console.warn("hyprctl stderr: " + text.trim())
                }
            }
        }
        onExited: exitCode => {
            console.log("hyprctl exited with code " + exitCode)
        }
    }

    property var previousAmbxstBinds: ({})
    property var previousCustomBinds: []
    property bool hasPreviousBinds: false

    property Timer applyTimer: Timer {
        interval: 100
        repeat: false
        onTriggered: applyKeybindsInternal()
    }

    function applyKeybinds() {
        applyTimer.restart();
    }

    // Helper function to check if an action is compatible with the current layout
    function isActionCompatibleWithLayout(action) {
        // If no compositor specified, action works everywhere
        if (!action.compositor)
            return true;

        // If compositor type is not hyprland, skip (future-proofing)
        if (action.compositor.type && action.compositor.type !== "hyprland")
            return false;

        // If no layouts specified or empty array, action works in all layouts
        if (!action.compositor.layouts || action.compositor.layouts.length === 0)
            return true;

        // Check if current layout is in the allowed list
        const currentLayout = GlobalStates.hyprlandLayout;
        return action.compositor.layouts.indexOf(currentLayout) !== -1;
    }

    function cloneKeybind(keybind) {
        return {
            modifiers: keybind.modifiers ? keybind.modifiers.slice() : [],
            key: keybind.key || ""
        };
    }

    function storePreviousBinds() {
        if (!Config.keybindsLoader.loaded)
            return;

        const ambxst = Config.keybindsLoader.adapter.ambxst;

        // Store dashboard keybinds
        previousAmbxstBinds = {
            dashboard: {
                widgets: cloneKeybind(ambxst.dashboard.widgets),
                clipboard: cloneKeybind(ambxst.dashboard.clipboard),
                emoji: cloneKeybind(ambxst.dashboard.emoji),
                tmux: cloneKeybind(ambxst.dashboard.tmux),
                notes: cloneKeybind(ambxst.dashboard.notes)
            },
            system: {
                overview: cloneKeybind(ambxst.system.overview),
                powermenu: cloneKeybind(ambxst.system.powermenu),
                config: cloneKeybind(ambxst.system.config),
                lockscreen: cloneKeybind(ambxst.system.lockscreen),
                tools: cloneKeybind(ambxst.system.tools),
                screenshot: cloneKeybind(ambxst.system.screenshot),
                screenrecord: cloneKeybind(ambxst.system.screenrecord),
                lens: cloneKeybind(ambxst.system.lens),
                reload: ambxst.system.reload ? cloneKeybind(ambxst.system.reload) : null,
                quit: ambxst.system.quit ? cloneKeybind(ambxst.system.quit) : null,
                toggleBar: ambxst.system.toggleBar ? cloneKeybind(ambxst.system.toggleBar) : null,
                notifications: ambxst.system.notifications ? cloneKeybind(ambxst.system.notifications) : null
            }
        };

        // Store custom keybinds
        const customBinds = Config.keybindsLoader.adapter.custom;
        previousCustomBinds = [];
        if (customBinds && customBinds.length > 0) {
            for (let i = 0; i < customBinds.length; i++) {
                const bind = customBinds[i];
                if (bind.keys) {
                    let keys = [];
                    for (let k = 0; k < bind.keys.length; k++) {
                        keys.push(cloneKeybind(bind.keys[k]));
                    }
                    previousCustomBinds.push({
                        keys: keys
                    });
                } else {
                    previousCustomBinds.push(cloneKeybind(bind));
                }
            }
        }

        hasPreviousBinds = true;
    }

    function applyKeybindsInternal() {
        if (!Config.keybindsLoader.loaded) {
            console.log("HyprlandKeybinds: Esperando que se cargue el adapter...");
            return;
        }

        if (!GlobalStates.hyprlandLayoutReady) {
            console.log("HyprlandKeybinds: Esperando que se detecte el layout de Hyprland...");
            return;
        }

        if (!GlobalStates.hyprlandParserReady) {
            console.log("HyprlandKeybinds: Esperando que se detecte el parser de Hyprland...");
            return;
        }

        const isLuaParser = GlobalStates.isLuaParser;

        console.log("HyprlandKeybinds: Aplicando keybindings (layout: " + GlobalStates.hyprlandLayout + ", isLua: " + isLuaParser + ")...");

        // Helper functions (Legacy)
        function formatModifiers(modifiers) {
            if (!modifiers || modifiers.length === 0)
                return "";
            return modifiers.join(" ");
        }

        function createBindCommand(keybind, flags) {
            const mods = formatModifiers(keybind.modifiers);
            const key = keybind.key;
            const dispatcher = keybind.dispatcher;
            const argument = keybind.argument || "";
            const bindKeyword = flags ? `bind${flags}` : "bind";
            if (flags === "m" && !argument) {
                return `keyword ${bindKeyword} ${mods},${key},${dispatcher}`;
            }
            return `keyword ${bindKeyword} ${mods},${key},${dispatcher},${argument}`;
        }

        function createUnbindCommand(keybind) {
            const mods = formatModifiers(keybind.modifiers);
            const key = keybind.key;
            return `keyword unbind ${mods},${key}`;
        }

        function createUnbindFromKey(keyObj) {
            const mods = formatModifiers(keyObj.modifiers);
            const key = keyObj.key;
            return `keyword unbind ${mods},${key}`;
        }

        function createBindFromKeyAction(keyObj, action) {
            const mods = formatModifiers(keyObj.modifiers);
            const key = keyObj.key;
            const resolved = resolveAction(action);
            const dispatcher = resolved.dispatcher;
            const argument = resolved.argument || "";
            if (!dispatcher) return "";
            const flags = action.flags || (action.id && action.id.endsWith("-locked") ? "l" : "");
            const bindKeyword = flags ? `bind${flags}` : "bind";
            if (flags === "m" && !argument) {
                return `keyword ${bindKeyword} ${mods},${key},${dispatcher}`;
            }
            return `keyword ${bindKeyword} ${mods},${key},${dispatcher},${argument}`;
        }

        // Helper functions (Lua)
        function createUnbindCommandLua(keybind) {
            if (!keybind) return "";
            const mods = keybind.modifiers && keybind.modifiers.length > 0 ? keybind.modifiers.join(" + ") : "";
            const key = keybind.key || "";
            const bindStr = mods ? `${mods} + ${key}` : key;
            return `hl.unbind(${JSON.stringify(bindStr)})`;
        }

        function createUnbindFromKeyLua(keyObj) {
            if (!keyObj) return "";
            const mods = keyObj.modifiers && keyObj.modifiers.length > 0 ? keyObj.modifiers.join(" + ") : "";
            const key = keyObj.key || "";
            const bindStr = mods ? `${mods} + ${key}` : key;
            return `hl.unbind(${JSON.stringify(bindStr)})`;
        }

        // Action Resolver for new binds.json format
        function resolveAction(keybind) {
            let dispatcher = keybind.dispatcher || "";
            let argument = keybind.argument || "";
            let luaExpr = "";
            const id = (keybind.action && keybind.action.id) ? keybind.action.id : (keybind.id || "");
            const args = (keybind.action && keybind.action.args) ? keybind.action.args : (keybind.args || {});

            if (id) {
                if (id.startsWith("ambxst.")) {
                    dispatcher = "exec";
                    const sub = id.replace("ambxst.", "");
                    if (sub === "reload") argument = "ambxst reload";
                    else if (sub === "quit") argument = "ambxst quit";
                    else if (sub === "overview") argument = "ambxst run overview";
                    else if (sub === "powermenu") argument = "ambxst run powermenu";
                    else if (sub === "config") argument = "ambxst run config";
                    else if (sub === "launcher") argument = "ambxst run launcher";
                    else if (sub === "dashboard") argument = "ambxst run dashboard";
                    else if (sub === "tools") argument = "ambxst run tools";
                    else if (sub === "screenshot") argument = "ambxst run screenshot";
                    else if (sub === "screenrecord") argument = "ambxst run screenrecord";
                    else if (sub === "lens") argument = "ambxst run lens";
                    else if (sub === "clipboard") argument = "ambxst run dashboard-clipboard";
                    else if (sub === "emoji") argument = "ambxst run dashboard-emoji";
                    else if (sub === "notes") argument = "ambxst run dashboard-notes";
                    else if (sub === "tmux") argument = "ghostty";
                    else argument = "ambxst run " + sub;
                } else if (id === "system.lock" || id === "system.lock-locked") {
                    dispatcher = "exec";
                    argument = "hyprlock";
                    luaExpr = `hl.dsp.exec_cmd("hyprlock")`;
                } else if (id === "system.calculator") {
                    dispatcher = "exec";
                    argument = "gnome-calculator";
                    luaExpr = `hl.dsp.exec_cmd("gnome-calculator")`;
                } else if (id === "workspace.switch") {
                    const idx = args.index || "1";
                    dispatcher = "workspace";
                    argument = idx;
                    const numIdx = Number(idx);
                    luaExpr = `hl.dsp.focus({ workspace = ${isNaN(numIdx) ? JSON.stringify(idx) : numIdx} })`;
                } else if (id === "workspace.move-window") {
                    const idx = args.index || "1";
                    dispatcher = "movetoworkspace";
                    argument = idx;
                    const numIdx = Number(idx);
                    luaExpr = `hl.dsp.window.move({ workspace = ${isNaN(numIdx) ? JSON.stringify(idx) : numIdx} })`;
                } else if (id === "workspace.switch-occupied") {
                    const off = args.offset || "+1";
                    const target = String(off).startsWith("-") ? "m-1" : "m+1";
                    dispatcher = "workspace";
                    argument = target;
                    luaExpr = `hl.dsp.focus({ workspace = "${target}" })`;
                } else if (id === "workspace.switch-relative") {
                    const off = args.offset || "+1";
                    const target = String(off).startsWith("-") ? "e-1" : "e+1";
                    dispatcher = "workspace";
                    argument = target;
                    luaExpr = `hl.dsp.focus({ workspace = "${target}" })`;
                } else if (id === "workspace.toggle-special") {
                    dispatcher = "togglespecialworkspace";
                    argument = "";
                    luaExpr = `hl.dsp.focus({ special_workspace = "" })`;
                } else if (id === "workspace.move-window-special") {
                    dispatcher = "movetoworkspace";
                    argument = "special";
                    luaExpr = `hl.dsp.window.move({ special_workspace = "" })`;
                } else if (id === "window.close") {
                    dispatcher = "killactive";
                    argument = "";
                    luaExpr = `hl.dsp.window.close()`;
                } else if (id === "window.focus" || id === "scrolling.focus") {
                    const dir = args.direction || "l";
                    dispatcher = "movefocus";
                    argument = dir;
                    luaExpr = `hl.dsp.focus({ direction = ${JSON.stringify(dir)} })`;
                } else if (id === "window.move" || id === "scrolling.move-window") {
                    const dir = args.direction || "l";
                    dispatcher = "movewindow";
                    argument = dir;
                    luaExpr = `hl.dsp.window.move({ direction = ${JSON.stringify(dir)} })`;
                } else if (id === "window.drag") {
                    dispatcher = "movewindow";
                    argument = "";
                    luaExpr = `hl.dsp.window.drag()`;
                } else if (id === "window.resize-drag") {
                    dispatcher = "resizewindow";
                    argument = "";
                    luaExpr = `hl.dsp.window.resize()`;
                } else if (id === "window.resize") {
                    const delta = args.delta || "50 0";
                    dispatcher = "resizeactive";
                    argument = delta;
                    const parts = delta.split(" ");
                    const dx = parseInt(parts[0]) || 0;
                    const dy = parseInt(parts[1]) || 0;
                    luaExpr = `hl.dsp.window.resize({ x = ${dx}, y = ${dy}, relative = true })`;
                } else if (id === "command.run") {
                    dispatcher = "exec";
                    argument = args.command || "";
                    luaExpr = `hl.dsp.exec_cmd(${JSON.stringify(argument)})`;
                } else if (id === "audio.volume-up") {
                    dispatcher = "exec";
                    argument = "pamixer -i 5";
                    luaExpr = `hl.dsp.exec_cmd("pamixer -i 5")`;
                } else if (id === "audio.volume-down") {
                    dispatcher = "exec";
                    argument = "pamixer -d 5";
                    luaExpr = `hl.dsp.exec_cmd("pamixer -d 5")`;
                } else if (id === "audio.mute-toggle") {
                    dispatcher = "exec";
                    argument = "pamixer -t";
                    luaExpr = `hl.dsp.exec_cmd("pamixer -t")`;
                } else if (id === "brightness.up") {
                    dispatcher = "exec";
                    argument = "brightnessctl s +5%";
                    luaExpr = `hl.dsp.exec_cmd("brightnessctl s +5%")`;
                } else if (id === "brightness.down") {
                    dispatcher = "exec";
                    argument = "brightnessctl s 5%-";
                    luaExpr = `hl.dsp.exec_cmd("brightnessctl s 5%-")`;
                } else if (id === "media.play-pause" || id === "media.play-pause-locked") {
                    dispatcher = "exec";
                    argument = "playerctl play-pause";
                    luaExpr = `hl.dsp.exec_cmd("playerctl play-pause")`;
                } else if (id === "media.next") {
                    dispatcher = "exec";
                    argument = "playerctl next";
                    luaExpr = `hl.dsp.exec_cmd("playerctl next")`;
                } else if (id === "media.prev") {
                    dispatcher = "exec";
                    argument = "playerctl previous";
                    luaExpr = `hl.dsp.exec_cmd("playerctl previous")`;
                } else if (id.startsWith("scrolling.")) {
                    const subCmd = id.replace("scrolling.", "").replace(/-/g, "");
                    const argStr = args.direction || args.delta || args.index || "";
                    dispatcher = "scrolling:" + subCmd;
                    argument = argStr;
                    luaExpr = `hl.dsp.exec_raw(${JSON.stringify("scrolling:" + subCmd + (argStr ? " " + argStr : ""))})`;
                }
            }

            return { dispatcher: dispatcher || "", argument: argument, luaExpr: luaExpr };
        }

        function createBindCommandLua(keybind, flags) {
            if (!keybind) return "";
            const mods = keybind.modifiers && keybind.modifiers.length > 0 ? keybind.modifiers.join(" + ") : "";
            const key = keybind.key || "";
            const bindStr = mods ? `${mods} + ${key}` : key;
            const resolved = resolveAction(keybind);
            const dispatcher = resolved.dispatcher;
            const argument = resolved.argument;

            let dspExpr = resolved.luaExpr;
            if (!dspExpr) {
                if (dispatcher === "exec") {
                    dspExpr = `hl.dsp.exec_cmd(${JSON.stringify(argument)})`;
                } else if (dispatcher === "global") {
                    dspExpr = `hl.dsp.global(${JSON.stringify(argument)})`;
                } else if (dispatcher === "movewindow" && !argument) {
                    dspExpr = `hl.dsp.window.drag()`;
                } else if (dispatcher === "resizewindow" && !argument) {
                    dspExpr = `hl.dsp.window.resize()`;
                } else if (dispatcher) {
                    dspExpr = `hl.dsp.exec_raw(${JSON.stringify(dispatcher + (argument ? " " + argument : ""))})`;
                } else {
                    return "";
                }
            }

            let opts = [];
            if (flags) {
                if (flags.includes("l")) opts.push("locked = true");
                if (flags.includes("r")) opts.push("release = true");
                if (flags.includes("e")) opts.push("repeating = true");
                if (flags.includes("m")) opts.push("drag = true");
                if (flags.includes("n")) opts.push("non_consuming = true");
            }

            const bindArgs = opts.length > 0 ? `${JSON.stringify(bindStr)}, dsp, { ${opts.join(", ")} }` : `${JSON.stringify(bindStr)}, dsp`;
            return `do _G.ambxst_dsp = _G.ambxst_dsp or {}; local dsp = ${dspExpr}; _G.ambxst_dsp[${JSON.stringify(bindStr)}] = dsp; hl.bind(${bindArgs}) end`;
        }

        function createBindFromKeyActionLua(keyObj, action) {
            if (!keyObj || !action) return "";
            const mods = keyObj.modifiers && keyObj.modifiers.length > 0 ? keyObj.modifiers.join(" + ") : "";
            const key = keyObj.key || "";
            const bindStr = mods ? `${mods} + ${key}` : key;
            const resolved = resolveAction(action);
            const dispatcher = resolved.dispatcher;
            const argument = resolved.argument;
            const flags = action.flags || (action.id && action.id.endsWith("-locked") ? "l" : "");

            let dspExpr = resolved.luaExpr;
            if (!dspExpr) {
                if (dispatcher === "exec") {
                    dspExpr = `hl.dsp.exec_cmd(${JSON.stringify(argument)})`;
                } else if (dispatcher === "global") {
                    dspExpr = `hl.dsp.global(${JSON.stringify(argument)})`;
                } else if (dispatcher === "movewindow" && !argument) {
                    dspExpr = `hl.dsp.window.drag()`;
                } else if (dispatcher === "resizewindow" && !argument) {
                    dspExpr = `hl.dsp.window.resize()`;
                } else if (dispatcher) {
                    dspExpr = `hl.dsp.exec_raw(${JSON.stringify(dispatcher + (argument ? " " + argument : ""))})`;
                } else {
                    return "";
                }
            }

            let opts = [];
            if (flags) {
                if (flags.includes("l")) opts.push("locked = true");
                if (flags.includes("r")) opts.push("release = true");
                if (flags.includes("e")) opts.push("repeating = true");
                if (flags.includes("m")) opts.push("drag = true");
                if (flags.includes("n")) opts.push("non_consuming = true");
            }

            const bindArgs = opts.length > 0 ? `${JSON.stringify(bindStr)}, dsp, { ${opts.join(", ")} }` : `${JSON.stringify(bindStr)}, dsp`;
            return `do _G.ambxst_dsp = _G.ambxst_dsp or {}; local dsp = ${dspExpr}; _G.ambxst_dsp[${JSON.stringify(bindStr)}] = dsp; hl.bind(${bindArgs}) end`;
        }

        let unbindCommands = [];
        let batchCommands = [];
        let unbindCommandsLua = [];
        let batchCommandsLua = [];

        // Unbind previous keybinds if stored
        if (hasPreviousBinds) {
            if (previousAmbxstBinds.dashboard) {
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.dashboard.widgets));
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.dashboard.clipboard));
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.dashboard.emoji));
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.dashboard.tmux));
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.dashboard.notes));

                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.dashboard.widgets));
                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.dashboard.clipboard));
                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.dashboard.emoji));
                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.dashboard.tmux));
                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.dashboard.notes));
            }

            if (previousAmbxstBinds.system) {
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.system.overview));
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.system.powermenu));
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.system.config));
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.system.lockscreen));
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.system.tools));
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.system.screenshot));
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.system.screenrecord));
                unbindCommands.push(createUnbindCommand(previousAmbxstBinds.system.lens));
                if (previousAmbxstBinds.system.reload) unbindCommands.push(createUnbindCommand(previousAmbxstBinds.system.reload));
                if (previousAmbxstBinds.system.quit) unbindCommands.push(createUnbindCommand(previousAmbxstBinds.system.quit));
                if (previousAmbxstBinds.system.toggleBar) unbindCommands.push(createUnbindCommand(previousAmbxstBinds.system.toggleBar));

                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.system.overview));
                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.system.powermenu));
                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.system.config));
                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.system.lockscreen));
                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.system.tools));
                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.system.screenshot));
                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.system.screenrecord));
                unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.system.lens));
                if (previousAmbxstBinds.system.reload) unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.system.reload));
                if (previousAmbxstBinds.system.quit) unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.system.quit));
                if (previousAmbxstBinds.system.toggleBar) unbindCommandsLua.push(createUnbindCommandLua(previousAmbxstBinds.system.toggleBar));
            }

            for (let i = 0; i < previousCustomBinds.length; i++) {
                const prev = previousCustomBinds[i];
                if (prev.keys) {
                    for (let k = 0; k < prev.keys.length; k++) {
                        unbindCommands.push(createUnbindFromKey(prev.keys[k]));
                        unbindCommandsLua.push(createUnbindFromKeyLua(prev.keys[k]));
                    }
                } else {
                    unbindCommands.push(createUnbindCommand(prev));
                    unbindCommandsLua.push(createUnbindCommandLua(prev));
                }
            }
        }

        const ambxst = Config.keybindsLoader.adapter.ambxst;
        const dashboard = ambxst.dashboard;
        unbindCommands.push(createUnbindCommand(dashboard.widgets));
        unbindCommands.push(createUnbindCommand(dashboard.clipboard));
        unbindCommands.push(createUnbindCommand(dashboard.emoji));
        unbindCommands.push(createUnbindCommand(dashboard.tmux));
        unbindCommands.push(createUnbindCommand(dashboard.notes));

        unbindCommandsLua.push(createUnbindCommandLua(dashboard.widgets));
        unbindCommandsLua.push(createUnbindCommandLua(dashboard.clipboard));
        unbindCommandsLua.push(createUnbindCommandLua(dashboard.emoji));
        unbindCommandsLua.push(createUnbindCommandLua(dashboard.tmux));
        unbindCommandsLua.push(createUnbindCommandLua(dashboard.notes));

        batchCommands.push(createBindCommand(dashboard.widgets, dashboard.widgets.flags || ""));
        batchCommands.push(createBindCommand(dashboard.clipboard, dashboard.clipboard.flags || ""));
        batchCommands.push(createBindCommand(dashboard.emoji, dashboard.emoji.flags || ""));
        batchCommands.push(createBindCommand(dashboard.tmux, dashboard.tmux.flags || ""));
        batchCommands.push(createBindCommand(dashboard.notes, dashboard.notes.flags || ""));

        batchCommandsLua.push(createBindCommandLua(dashboard.widgets, dashboard.widgets.flags || ""));
        batchCommandsLua.push(createBindCommandLua(dashboard.clipboard, dashboard.clipboard.flags || ""));
        batchCommandsLua.push(createBindCommandLua(dashboard.emoji, dashboard.emoji.flags || ""));
        batchCommandsLua.push(createBindCommandLua(dashboard.tmux, dashboard.tmux.flags || ""));
        batchCommandsLua.push(createBindCommandLua(dashboard.notes, dashboard.notes.flags || ""));

        const system = ambxst.system;
        unbindCommands.push(createUnbindCommand(system.overview));
        unbindCommands.push(createUnbindCommand(system.powermenu));
        unbindCommands.push(createUnbindCommand(system.config));
        unbindCommands.push(createUnbindCommand(system.lockscreen));
        unbindCommands.push(createUnbindCommand(system.tools));
        unbindCommands.push(createUnbindCommand(system.screenshot));
        unbindCommands.push(createUnbindCommand(system.screenrecord));
        unbindCommands.push(createUnbindCommand(system.lens));
        if (system.reload) unbindCommands.push(createUnbindCommand(system.reload));
        if (system.quit) unbindCommands.push(createUnbindCommand(system.quit));
        if (system.toggleBar) unbindCommands.push(createUnbindCommand(system.toggleBar));
        if (system.notifications) unbindCommands.push(createUnbindCommand(system.notifications));

        unbindCommandsLua.push(createUnbindCommandLua(system.overview));
        unbindCommandsLua.push(createUnbindCommandLua(system.powermenu));
        unbindCommandsLua.push(createUnbindCommandLua(system.config));
        unbindCommandsLua.push(createUnbindCommandLua(system.lockscreen));
        unbindCommandsLua.push(createUnbindCommandLua(system.tools));
        unbindCommandsLua.push(createUnbindCommandLua(system.screenshot));
        unbindCommandsLua.push(createUnbindCommandLua(system.screenrecord));
        unbindCommandsLua.push(createUnbindCommandLua(system.lens));
        if (system.reload) unbindCommandsLua.push(createUnbindCommandLua(system.reload));
        if (system.quit) unbindCommandsLua.push(createUnbindCommandLua(system.quit));
        if (system.toggleBar) unbindCommandsLua.push(createUnbindCommandLua(system.toggleBar));
        if (system.notifications) unbindCommandsLua.push(createUnbindCommandLua(system.notifications));

        batchCommands.push(createBindCommand(system.overview, system.overview.flags || ""));
        batchCommands.push(createBindCommand(system.powermenu, system.powermenu.flags || ""));
        batchCommands.push(createBindCommand(system.config, system.config.flags || ""));
        batchCommands.push(createBindCommand(system.lockscreen, system.lockscreen.flags || ""));
        batchCommands.push(createBindCommand(system.tools, system.tools.flags || ""));
        batchCommands.push(createBindCommand(system.screenshot, system.screenshot.flags || ""));
        batchCommands.push(createBindCommand(system.screenrecord, system.screenrecord.flags || ""));
        batchCommands.push(createBindCommand(system.lens, system.lens.flags || ""));
        if (system.reload) batchCommands.push(createBindCommand(system.reload, system.reload.flags || ""));
        if (system.quit) batchCommands.push(createBindCommand(system.quit, system.quit.flags || ""));
        if (system.toggleBar) batchCommands.push(createBindCommand(system.toggleBar, system.toggleBar.flags || ""));
        if (system.notifications) batchCommands.push(createBindCommand(system.notifications, system.notifications.flags || ""));

        batchCommandsLua.push(createBindCommandLua(system.overview, system.overview.flags || ""));
        batchCommandsLua.push(createBindCommandLua(system.powermenu, system.powermenu.flags || ""));
        batchCommandsLua.push(createBindCommandLua(system.config, system.config.flags || ""));
        batchCommandsLua.push(createBindCommandLua(system.lockscreen, system.lockscreen.flags || ""));
        batchCommandsLua.push(createBindCommandLua(system.tools, system.tools.flags || ""));
        batchCommandsLua.push(createBindCommandLua(system.screenshot, system.screenshot.flags || ""));
        batchCommandsLua.push(createBindCommandLua(system.screenrecord, system.screenrecord.flags || ""));
        batchCommandsLua.push(createBindCommandLua(system.lens, system.lens.flags || ""));
        if (system.reload) batchCommandsLua.push(createBindCommandLua(system.reload, system.reload.flags || ""));
        if (system.quit) batchCommandsLua.push(createBindCommandLua(system.quit, system.quit.flags || ""));
        if (system.toggleBar) batchCommandsLua.push(createBindCommandLua(system.toggleBar, system.toggleBar.flags || ""));
        if (system.notifications) batchCommandsLua.push(createBindCommandLua(system.notifications, system.notifications.flags || ""));

        const customBinds = Config.keybindsLoader.adapter.custom;
        if (customBinds && customBinds.length > 0) {
            for (let i = 0; i < customBinds.length; i++) {
                const bind = customBinds[i];
                if (bind.enabled === false) continue;

                if (bind.keys && bind.actions) {
                    for (let k = 0; k < bind.keys.length; k++) {
                        for (let a = 0; a < bind.actions.length; a++) {
                            const action = bind.actions[a];
                            if (isActionCompatibleWithLayout(action)) {
                                const bindCmd = createBindFromKeyAction(bind.keys[k], action);
                                const bindCmdLua = createBindFromKeyActionLua(bind.keys[k], action);
                                if (bindCmd) {
                                    unbindCommands.push(createUnbindFromKey(bind.keys[k]));
                                    batchCommands.push(bindCmd);
                                }
                                if (bindCmdLua) {
                                    unbindCommandsLua.push(createUnbindFromKeyLua(bind.keys[k]));
                                    batchCommandsLua.push(bindCmdLua);
                                }
                            }
                        }
                    }
                } else {
                    const flags = bind.flags || "";
                    const bindCmd = createBindCommand(bind, flags);
                    const bindCmdLua = createBindCommandLua(bind, flags);
                    if (bindCmd) {
                        unbindCommands.push(createUnbindCommand(bind));
                        batchCommands.push(bindCmd);
                    }
                    if (bindCmdLua) {
                        unbindCommandsLua.push(createUnbindCommandLua(bind));
                        batchCommandsLua.push(bindCmdLua);
                    }
                }
            }
        }

        storePreviousBinds();

        lastApplyTime = Date.now();

        if (isLuaParser) {
            const allLuaCode = unbindCommandsLua.concat(batchCommandsLua).filter(c => c !== "");
            console.log("HyprlandKeybinds: Applying keybindings via hyprctl eval (Lua parser)");
            hyprctlProcess.command = ["hyprctl", "eval", allLuaCode.join(";\n")];
            hyprctlProcess.running = true;
        } else {
            const fullBatchCommand = unbindCommands.join("; ") + "; " + batchCommands.join("; ");
            console.log("HyprlandKeybinds: Applying keybindings via hyprctl batch (Legacy parser)");
            hyprctlProcess.command = ["hyprctl", "--batch", fullBatchCommand];
            hyprctlProcess.running = true;
        }
    }

    property var keybindsLoaderLoaded: Config.keybindsLoader?.loaded
    onKeybindsLoaderLoadedChanged: applyKeybinds()

    // Re-apply keybindings after a delay to prevent startup overwrites
    property Timer startupReapplyTimer: Timer {
        id: startupReapplyTimer
        interval: 2000
        repeat: false
        onTriggered: {
            console.log("delayed re-applying keybindings after startup")
            applyKeybinds();
        }
    }

    // Re-apply keybinds when layout changes
    property var globalStatesLayout: GlobalStates.hyprlandLayout
    property var globalStatesLayoutReady: GlobalStates.hyprlandLayoutReady
    property var globalStatesIsLuaParser: GlobalStates.isLuaParser
    property var globalStatesParserReady: GlobalStates.hyprlandParserReady

    onGlobalStatesLayoutChanged: {
        console.log("HyprlandKeybinds: Layout changed to " + GlobalStates.hyprlandLayout + ", reapplying keybindings...");
        applyKeybinds();
    }
    onGlobalStatesLayoutReadyChanged: {
        if (GlobalStates.hyprlandLayoutReady) {
            applyKeybinds();
            startupReapplyTimer.start();
        }
    }
    onGlobalStatesIsLuaParserChanged: {
        console.log("HyprlandKeybinds: isLuaParser changed, reapplying keybindings...");
        applyKeybinds();
    }
    onGlobalStatesParserReadyChanged: {
        if (GlobalStates.hyprlandParserReady) {
            console.log("HyprlandKeybinds: hyprlandParserReady changed, reapplying keybindings...");
            applyKeybinds();
        }
    }

    property Connections hyprlandConnections: Connections {
        ignoreUnknownSignals: true
        enabled: Hyprland != null
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                // ignore configreloaded events triggered by our own hyprctl calls (use 5s window)
                if (Date.now() - lastApplyTime < 5000) {
                    return;
                }
                console.log("HyprlandKeybinds: Detectado configreloaded, reaplicando keybindings...");
                applyKeybinds();
            }
        }
    }

    Component.onCompleted: {
        // Si el loader ya está cargado, aplicar inmediatamente
        if (Config.keybindsLoader?.loaded) {
            applyKeybinds();
        }
    }
}
