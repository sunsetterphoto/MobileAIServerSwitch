import QtQuick
import org.kde.plasma.configuration

// Category/source syntax verified against the installed
// org.kde.plasma.systemmonitor, org.kde.desktopcontainment and (custom,
// working) io.github.sunsetterphoto.healthpanel plasmoids: `source` is
// resolved relative to contents/ui/ (not contents/config/), so the config
// page files live in ../ui/config*.qml, referenced here by bare filename.
ConfigModel {
    ConfigCategory {
        name: "General"
        icon: "configure"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: "Network"
        icon: "preferences-system-network"
        source: "configNetwork.qml"
    }
    ConfigCategory {
        name: "Services"
        icon: "preferences-system-services"
        source: "configServices.qml"
    }
    ConfigCategory {
        name: "Mode"
        icon: "preferences-system-power-management"
        source: "configMode.qml"
    }
    ConfigCategory {
        name: "Firewall"
        icon: "preferences-security-firewall"
        source: "configFirewall.qml"
    }
    ConfigCategory {
        name: "Remote Access"
        icon: "preferences-system-network-remote"
        source: "configRemote.qml"
    }
}
