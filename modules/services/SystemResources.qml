pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
pragma ComponentBehavior: Bound

/**
 * System resource monitoring service
 * Tracks CPU, GPU, RAM and disk usage percentages
 */
Singleton {
    id: root

    // CPU metrics
    property real cpuUsage: 0.0
    property var cpuPrevTotal: 0
    property var cpuPrevIdle: 0
    property string cpuModel: ""
    property int cpuTemp: -1  // CPU temperature in Celsius, -1 if unavailable

    // RAM metrics
    property real ramUsage: 0.0
    property real ramTotal: 0
    property real ramUsed: 0
    property real ramAvailable: 0

    // GPU metrics - supports multiple GPUs
    property var gpuUsages: []          // Array of usage percentages
    property var gpuVendors: []         // Array of vendor strings
    property var gpuNames: []           // Array of GPU names
    property int gpuCount: 0
    property bool gpuDetected: false
    
    // GPU temperature metrics - supports multiple GPUs
    property var gpuTemps: []            // Array of temperatures in Celsius, -1 if unavailable
    
    // Legacy single GPU properties (for backward compatibility)
    property real gpuUsage: gpuUsages.length > 0 ? gpuUsages[0] : 0.0
    property string gpuVendor: gpuVendors.length > 0 ? gpuVendors[0] : "unknown"
    property int gpuTemp: gpuTemps.length > 0 ? gpuTemps[0] : -1

    // Disk metrics - map of mountpoint to usage percentage
    property var diskUsage: ({})
    property var diskUsed: ({})
    property var diskTotal: ({})

    // Disk types - map of mountpoint to type ("ssd", "hdd", or "unknown")
    property var diskTypes: ({})

    // Validated disk list
    property var validDisks: []

    // Update interval in milliseconds
    property int updateInterval: 2000

    // History data for charts (max 50 points)
    property var cpuHistory: []
    property var ramHistory: []
    property var gpuHistories: []       // Array of arrays - one history per GPU
    property var cpuTempHistory: []     // CPU temperature history
    property var gpuTempHistories: []   // Array of arrays - one temp history per GPU
    property int maxHistoryPoints: 50
    
    // Total data points collected (continues incrementing forever)
    property int totalDataPoints: 0

    // Unified System Monitor Process
    Connections {
        ignoreUnknownSignals: true
        target: DaemonClient
        function onSystemResourcesReceived(stats) {
            root.cpuUsage = stats.cpu.usage;
            root.cpuTemp = stats.cpu.temp;
            
            root.cpuModel = stats.cpu.model || "";
            
            root.ramUsage = stats.ram.usage;
            root.ramTotal = stats.ram.total;
            root.ramUsed = stats.ram.used;
            root.ramAvailable = stats.ram.available;
            
            root.diskUsage = stats.disk;
            root.diskUsed = stats.disk_used || ({});
            root.diskTotal = stats.disk_total || ({});
            root.diskTypes = stats.disk_type || ({});
            
            root.gpuDetected = stats.gpu.detected;
            if (stats.gpu.detected) {
                if (root.gpuCount !== stats.gpu.count) {
                    root.gpuCount = stats.gpu.count;
                    root.gpuVendors = Array(stats.gpu.count).fill(stats.gpu.vendor);
                }
                root.gpuUsages = stats.gpu.usages;
                root.gpuTemps = stats.gpu.temps;
                root.gpuNames = stats.gpu.names || [];
            }
            
            root.updateHistory();
        }
    }

    Component.onCompleted: {
        Qt.callLater(() => {
            validateDisks();
        });
    }

    // watch for config changes and revalidate disks
    property var configSystemDisks: Config.system?.disks ?? null
    onConfigSystemDisksChanged: {
        if (Config.initialLoadComplete && Config.system) {
            root.validateDisks();
        }
    }

    // Validate disks when Config is ready
    property bool configReady: Config.initialLoadComplete
    onConfigReadyChanged: {
        if (configReady) {
            validateDisks();
        }
    }

    // Restart monitor when disks change
    onValidDisksChanged: {
        // Handled by daemon
    }

    // Detect GPU vendor and availability
    function detectGPU() {
        // Handled by daemon
    }

    // Validate configured disks and fall back to "/" if invalid
    function validateDisks() {
        const configuredDisks = Config.system.disks || ["/"];
        let newValidDisks = [];

        for (let i = 0; i < configuredDisks.length; i++) {
            const disk = configuredDisks[i];
            if (disk && typeof disk === 'string' && disk.trim() !== '') {
                newValidDisks.push(disk.trim());
            }
        }

        // Ensure at least "/" is present
        if (newValidDisks.length === 0) {
            newValidDisks = ["/"];
        }
        
        // Assign the new array to trigger onValidDisksChanged
        validDisks = newValidDisks;
    }

    // Update history arrays with current values
    function updateHistory() {
        // Increment total data points counter
        totalDataPoints++;
        
        // Add CPU history
        let newCpuHistory = cpuHistory.slice();
        newCpuHistory.push(cpuUsage / 100);
        if (newCpuHistory.length > maxHistoryPoints) {
            newCpuHistory.shift();
        }
        cpuHistory = newCpuHistory;

        // Add CPU temperature history
        let newCpuTempHistory = cpuTempHistory.slice();
        newCpuTempHistory.push(cpuTemp);
        if (newCpuTempHistory.length > maxHistoryPoints) {
            newCpuTempHistory.shift();
        }
        cpuTempHistory = newCpuTempHistory;

        // Add RAM history
        let newRamHistory = ramHistory.slice();
        newRamHistory.push(ramUsage / 100);
        if (newRamHistory.length > maxHistoryPoints) {
            newRamHistory.shift();
        }
        ramHistory = newRamHistory;

        // Add GPU histories if detected
        if (gpuDetected && gpuCount > 0) {
            let newGpuHistories = gpuHistories.slice();
            let newGpuTempHistories = gpuTempHistories.slice();
            
            // Initialize histories array if needed
            while (newGpuHistories.length < gpuCount) {
                newGpuHistories.push([]);
            }
            while (newGpuTempHistories.length < gpuCount) {
                newGpuTempHistories.push([]);
            }
            
            // Update each GPU's history
            for (let i = 0; i < gpuCount; i++) {
                let gpuHist = newGpuHistories[i].slice();
                gpuHist.push((gpuUsages[i] || 0) / 100);
                if (gpuHist.length > maxHistoryPoints) {
                    gpuHist.shift();
                }
                newGpuHistories[i] = gpuHist;

                let gpuTempHist = newGpuTempHistories[i].slice();
                gpuTempHist.push(gpuTemps[i] !== undefined ? gpuTemps[i] : -1);
                if (gpuTempHist.length > maxHistoryPoints) {
                    gpuTempHist.shift();
                }
                newGpuTempHistories[i] = gpuTempHist;
            }
            
            gpuHistories = newGpuHistories;
            gpuTempHistories = newGpuTempHistories;
        }
    }


}
