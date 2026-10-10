import Foundation
import Testing
@testable import FirmDropCore

@Suite struct ADBDownloadTests {
    private let source = FlashDevice(target: "0x00100000", connection: 42, productID: 0x6860, isDownloadMode: false)
    private let listing = "TEST_SAMSUNG device usb:1048576X product:pa1q model:SM_S931B transport_id:7\n"

    private func write(_ value: String, to name: String, in directory: URL) throws {
        try value.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
    }

    private func executable(_ name: String, body: String, in directory: URL) throws -> URL {
        let url = directory.appending(path: name)
        try ("#!/bin/sh\ncd -- \"$(dirname -- \"$0\")\"\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func fixture(in directory: URL, startsServer: Bool = false) throws -> (ADBDownload, FlashEngine) {
        try write(listing, to: "devices", in: directory)
        try write("samsung\n", to: "manufacturer", in: directory)
        try write("true\n", to: "maintenance", in: directory)
        try write("@firmdrop\tDEVICE\t0x00100000\t42\t26720\tother\n", to: "usb", in: directory)
        if startsServer { try write("", to: "no-server", in: directory) }
        let adb = try executable("fake-adb", body: #"""
        printf '%s\n' "$*" >> calls
        printf '%s\n' "$ADB_MDNS" >> mdns
        case "$*" in
          'devices -l')
            cat devices
            if [ -f next-devices ]; then mv next-devices devices; fi
            ;;
          '-t 7 shell getprop ro.product.manufacturer') cat manufacturer ;;
          '-t 7 shell getprop persist.sys.is_in_maintenance_mode')
            cat maintenance
            if [ -f next-usb ]; then mv next-usb usb; fi
            ;;
          '-t 7 reboot download') touch rebooted ;;
          'start-server')
            if [ -f no-server ]; then rm no-server; echo '* daemon started successfully' >&2; fi
            ;;
          'kill-server') touch killed ;;
          *) exit 99 ;;
        esac
        """#, in: directory)
        let engine = try executable("fake-engine", body: "cat usb\n", in: directory)
        return (ADBDownload(executable: adb), FlashEngine(executable: engine))
    }

    private func wasRebooted(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: "rebooted").path)
    }

    private func wasKilled(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: "killed").path)
    }

    @Test func parsesOnlyPhysicalADBTransports() {
        let device = ADBDevice(line: listing)
        #expect(device?.serial == "TEST_SAMSUNG")
        #expect(device?.transport == 7)
        #expect(device?.state == "device")
        for line in [
            "List of devices attached", "* daemon started successfully",
            "192.0.2.1:5555 device model:SM_S931B transport_id:8",
            "emulator-5554 device product:sdk transport_id:9",
            "TEST device usb:1048576X transport_id:0",
            "TEST device usb:1048576X transport_id:bad",
            "TEST recovery usb:1048576X transport_id:7",
        ] {
            #expect(ADBDevice(line: line) == nil)
        }
    }

    @Test func findsBundledExecutablesIncludingSymlinksAndRejectsDirectories() async throws {
        try await withTemporaryDirectory { directory in
            let file = directory.appending(path: "adb")
            try write("not executable", to: "adb", in: directory)
            #expect(FileManager.default.firstExecutable(in: [directory, file]) == nil)
            let actual = try executable("real-adb", body: "exit 0\n", in: directory)
            let link = directory.appending(path: "adb-link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)
            #expect(FileManager.default.firstExecutable(in: [directory, file, link]) == link)
        }
    }

    @Test func rebootsOnlyTheVerifiedTransportWithMaintenanceActive() async throws {
        try await withTemporaryDirectory { root in
            let directory = root.appending(path: "ADB with spaces")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let (adb, engine) = try fixture(in: directory)
            try await adb.rebootToDownload(from: source, using: engine)
            #expect(wasRebooted(directory))
            let calls = try String(contentsOf: directory.appending(path: "calls"), encoding: .utf8)
            #expect(calls.contains("-t 7 shell getprop persist.sys.is_in_maintenance_mode\n"))
            #expect(calls.hasSuffix("-t 7 reboot download\n"))
            #expect(!calls.contains("-s "))
            #expect(!wasKilled(directory))
        }
    }

    @Test func stopsOnlyTheServerItStartedWithMDNSDisabled() async throws {
        try await withTemporaryDirectory { directory in
            let (adb, engine) = try fixture(in: directory, startsServer: true)
            try await adb.rebootToDownload(from: source, using: engine)
            let calls = try String(contentsOf: directory.appending(path: "calls"), encoding: .utf8)
            #expect(calls.hasSuffix("-t 7 reboot download\nkill-server\n"))
            let mdns = try String(contentsOf: directory.appending(path: "mdns"), encoding: .utf8)
            #expect(Set(mdns.split(separator: "\n")) == ["0"])

            try FileManager.default.removeItem(at: directory.appending(path: "killed"))
            try write("", to: "no-server", in: directory)
            try write("false\n", to: "maintenance", in: directory)
            await #expect(throws: ADBError.maintenanceRequired) {
                try await adb.rebootToDownload(from: source, using: engine)
            }
            #expect(wasKilled(directory))
        }
    }

    @Test(arguments: ["false\n", "\n", "unknown\n"])
    func refusesInactiveOrUnverifiableMaintenance(value: String) async throws {
        try await withTemporaryDirectory { directory in
            let (adb, engine) = try fixture(in: directory)
            try write(value, to: "maintenance", in: directory)
            await #expect(throws: ADBError.maintenanceRequired) {
                try await adb.rebootToDownload(from: source, using: engine)
            }
            #expect(!wasRebooted(directory))
        }
    }

    @Test(arguments: ["unauthorized", "offline"])
    func reportsAuthorizationAndOfflineStates(state: String) async throws {
        try await withTemporaryDirectory { directory in
            let (adb, engine) = try fixture(in: directory)
            try write("TEST_SAMSUNG \(state) usb:1048576X transport_id:7\n", to: "devices", in: directory)
            let expected: ADBError = state == "unauthorized" ? .unauthorized : .offline
            await #expect(throws: expected) { try await adb.rebootToDownload(from: source, using: engine) }
            #expect(!wasRebooted(directory))
        }
    }

    @Test func rejectsOtherManufacturersAndWirelessOnlyConnections() async throws {
        try await withTemporaryDirectory { directory in
            let (adb, engine) = try fixture(in: directory)
            try write("other\n", to: "manufacturer", in: directory)
            await #expect(throws: ADBError.notSamsung) { try await adb.rebootToDownload(from: source, using: engine) }
            try write("192.0.2.1:5555 device model:SM_S931B transport_id:7\n", to: "devices", in: directory)
            await #expect(throws: ADBError.noDevice) { try await adb.rebootToDownload(from: source, using: engine) }
            #expect(!wasRebooted(directory))
        }
    }

    @Test func refusesAmbiguousADBOrSamsungUSBConnections() async throws {
        try await withTemporaryDirectory { directory in
            let (adb, engine) = try fixture(in: directory)
            try write(listing + "SECOND device usb:2097152X transport_id:8\n", to: "devices", in: directory)
            await #expect(throws: ADBError.multipleDevices) { try await adb.rebootToDownload(from: source, using: engine) }
            try write(listing, to: "devices", in: directory)
            try write("@firmdrop\tDEVICE\t0x00100000\t42\t26720\tother\n@firmdrop\tDEVICE\t0x00200000\t43\t26720\tother\n", to: "usb", in: directory)
            await #expect(throws: ADBError.multipleDevices) { try await adb.rebootToDownload(from: source, using: engine) }
            #expect(!wasRebooted(directory))
        }
    }

    @Test func refusesTransportChangesBeforeReboot() async throws {
        try await withTemporaryDirectory { directory in
            let (adb, engine) = try fixture(in: directory)
            try write("SECOND device usb:1048576X transport_id:8\n", to: "next-devices", in: directory)
            await #expect(throws: ADBError.deviceChanged) { try await adb.rebootToDownload(from: source, using: engine) }
            #expect(!wasRebooted(directory))
        }
    }

    @Test func refusesUSBReconnectionsBeforeReboot() async throws {
        try await withTemporaryDirectory { directory in
            let (adb, engine) = try fixture(in: directory)
            try write("@firmdrop\tDEVICE\t0x00100000\t99\t26720\tother\n", to: "next-usb", in: directory)
            await #expect(throws: ADBError.deviceChanged) { try await adb.rebootToDownload(from: source, using: engine) }
            #expect(!wasRebooted(directory))
        }
    }

    @Test func propagatesADBFailuresWithoutSendingReboot() async throws {
        try await withTemporaryDirectory { directory in
            let (_, engine) = try fixture(in: directory)
            let url = try executable("broken-adb", body: "echo 'ADB failed'; exit 7\n", in: directory)
            await #expect(throws: FlashError.commandFailed(7, "ADB failed")) {
                try await ADBDownload(executable: url).rebootToDownload(from: source, using: engine)
            }
            #expect(!wasRebooted(directory))
        }
    }
}
