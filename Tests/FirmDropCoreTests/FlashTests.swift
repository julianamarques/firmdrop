import Foundation
import Testing
@testable import FirmDropCore

@Suite struct FlashTests {
    private let device = FlashDevice(target: "0x00100000", connection: 42, productID: 0x685d, isDownloadMode: true)
    private let names = [
        "BL_S931BXXU1AYB4_test.tar.md5", "AP_S931BXXU1AYB4_test.tar.md5",
        "CP_S931BXXU1AYB4_test.tar.md5", "HOME_CSC_OXM_S931BOXM1AYB4_test.tar.md5",
    ]

    private func packages(in directory: URL) throws -> [FlashSlot: FlashPackage] {
        let urls = try names.map { name in
            let url = directory.appending(path: name)
            try Data(repeating: 0, count: 512).write(to: url)
            return url
        }
        return try FlashPackage.select(urls).packages
    }

    private func executable(in directory: URL, body: String) throws -> URL {
        let url = directory.appending(path: "fake-engine")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    @Test func recognizesOnlyFirmwareSlots() {
        #expect(FlashSlot.identify("HOME_CSC_OXM_S931BOXM1AYB4.tar.md5") == .csc)
        #expect(FlashSlot.identify("AP_S931BXXU1AYB4.tar") == .ap)
        for name in ["firmware.zip", "AP_file.enc4", "USERDATA_file.tar", "AP_$(touch).tar", "../AP_x.tar", "AP_file.tar.md5.part"] {
            #expect(FlashSlot.identify(name) == nil)
        }
    }

    @Test func importLeavesTheCSCChoiceOpenAndRejectsAmbiguousSlots() async throws {
        try await withTemporaryDirectory { directory in
            let initial = try packages(in: directory)
            #expect(try FlashPackage.select(initial.values.map(\.url)).packages[.csc]?.preservesData == true)
            let reset = directory.appending(path: "CSC_OXM_S931BOXM1AYB4_test.tar.md5")
            try Data(repeating: 0, count: 512).write(to: reset)
            let urls = initial.values.map(\.url) + [reset]
            for order in [urls, urls.reversed()] {
                let selection = try FlashPackage.select(order)
                #expect(selection.packages[.csc] == nil)
                #expect(selection.packages.count == 3)
                #expect(selection.cscOptions.map(\.preservesData) == [true, false])
            }
            let duplicate = directory.appending(path: "AP_S931BXXU2AYC1_test.tar")
            try Data(repeating: 0, count: 512).write(to: duplicate)
            #expect(throws: FlashError.ambiguousSlot("AP")) { try FlashPackage.select(urls + [duplicate]) }
        }
    }

    @Test func commandTargetsOneConnectionAndKeepsPathsAsArguments() async throws {
        try await withTemporaryDirectory { root in
            let directory = root.appending(path: "firmware com espaços $(literal)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let selected = try packages(in: directory)
            let plan = try FlashPlan(model: "sm-s931b", packages: selected, device: device, reboot: false)
            let args = try plan.arguments()
            #expect(Array(args.prefix(5)) == ["--flash", "--target", "0x00100000", "--connection", "42"])
            #expect(args.contains("--preserve"))
            #expect(args.contains("--no-reboot"))
            #expect(args.filter { $0 == "--file" }.count == 4)
            #expect(args.contains(selected[.ap]!.url.path))
            #expect(!args.contains("--use-pit"))
            #expect(!args.contains("--resume"))
            #expect(try plan.arguments(resume: true).contains("--resume"))
            #expect(plan.packages.map(\.slot) == [.bl, .ap, .cp, .csc])
        }
    }

    @Test func rejectsWrongModelMissingSlotsAndMixedBuilds() async throws {
        try await withTemporaryDirectory { directory in
            var selected = try packages(in: directory)
            #expect(throws: (any Error).self) { try FlashPlan(model: "SM-S936B", packages: selected, device: device, reboot: true) }
            #expect(throws: (any Error).self) { try FlashPlan(model: "SM-S931B;cmd", packages: selected, device: device, reboot: true) }
            let missing = selected.filter { $0.key != .cp }
            #expect(throws: FlashError.missingSlot("CP")) { try FlashPlan(model: "SM-S931B", packages: missing, device: device, reboot: true) }
            let different = directory.appending(path: "BL_S931BXXU2AYC1_test.tar.md5")
            try Data(repeating: 0, count: 512).write(to: different)
            selected[.bl] = try FlashPackage(url: different)
            #expect(throws: FlashError.mixedBuilds) { try FlashPlan(model: "SM-S931B", packages: selected, device: device, reboot: true) }
        }
    }

    @Test func rejectsChangesAfterReviewAndNonDownloadDevices() async throws {
        try await withTemporaryDirectory { directory in
            let selected = try packages(in: directory)
            let other = FlashDevice(target: device.target, connection: 42, productID: 0x6860, isDownloadMode: false)
            #expect(throws: FlashError.notInDownloadMode) { try FlashPlan(model: "SM-S931B", packages: selected, device: other, reboot: true) }
            let plan = try FlashPlan(model: "SM-S931B", packages: selected, device: device, reboot: true)
            try Data(repeating: 1, count: 1024).write(to: selected[.ap]!.url)
            #expect(throws: FlashError.changedPackage(names[1])) { try plan.arguments() }
        }
    }

    @Test func cleanCSCDoesNotSetPreserve() async throws {
        try await withTemporaryDirectory { directory in
            var selected = try packages(in: directory)
            let reset = directory.appending(path: "CSC_OXM_S931BOXM1AYB4.tar.md5")
            try Data(repeating: 0, count: 512).write(to: reset)
            selected[.csc] = try FlashPackage(url: reset)
            let plan = try FlashPlan(model: "SM-S931B", packages: selected, device: device, reboot: true)
            #expect(!plan.preservesData)
            #expect(try !plan.arguments().contains("--preserve"))
        }
    }

    @Test func parsesOnlyWellFormedEngineEvents() {
        #expect(FlashEvent(line: "@firmdrop\tDEVICE\t0x00100000\t42\t26717\tdownload") == .device(device))
        #expect(FlashEvent(line: "@firmdrop\tPROGRESS\t50\t100") == .progress(completed: 50, total: 100))
        #expect(FlashEvent(line: "@firmdrop\tPROGRESS\t100\t50") == nil)
        #expect(FlashEvent(line: "@firmdrop\tPROGRESS\t0\t0") == nil)
        #expect(FlashEvent(line: "@firmdrop\tDEVICE\t--all\t42\t26717\tdownload") == nil)
        #expect(FlashEvent(line: "@firmdrop\tDEVICE\t0x00100000\t0\t26717\tdownload") == nil)
        #expect(FlashEvent(line: "@firmdrop\tDONE\tunexpected") == nil)
        #expect(FlashEvent(line: "99% PASS") == nil)
    }

    @Test func keepsSplitUTF8AndCarriageReturnOutput() throws {
        var decoder = CommandLines()
        let bytes = Array("Conexão\r\n@firmdrop\tDONE".utf8)
        let index = bytes.firstIndex(of: 0xc3)!
        #expect(try decoder.append(Data(bytes[...index])).isEmpty)
        #expect(try decoder.append(Data(bytes[(index + 1)...])) == ["Conexão"])
        #expect(try decoder.append(Data(), finished: true) == ["@firmdrop\tDONE"])
        #expect(throws: FlashError.outputTooLarge) { try decoder.append(Data(repeating: 65, count: 70_000)) }
    }

    @Test func runnerDrainsOutputAndReportsExitStatus() async throws {
        let result = try await CommandRunner.run(URL(filePath: "/usr/bin/awk"), arguments: ["BEGIN { for (i=0; i<12000; i++) print \"output exceeding the pipe buffer\"; exit 7 }"])
        #expect(result.status == 7)
        #expect(result.truncated)
        #expect(!result.lines.isEmpty)
        #expect(throws: (any Error).self) { try result.requireSuccess() }
    }

    @Test func probeResumesOnlyWhenAskedAndErrorsHideEngineEvents() async throws {
        try await withTemporaryDirectory { directory in
            let url = try executable(in: directory, body: "printf '%s\\n' \"$*\" >> \"$(dirname \"$0\")/calls\"\nprintf '@firmdrop\\tPROBE\\t4\\n'\n")
            let engine = FlashEngine(executable: url)
            #expect(try await engine.probe(device) == 4)
            #expect(try await engine.probe(device, resume: true) == 4)
            let calls = try String(contentsOf: directory.appending(path: "calls"), encoding: .utf8)
            #expect(calls == "--probe --target 0x00100000 --connection 42\n--probe --target 0x00100000 --connection 42 --resume\n")

            let failing = try executable(in: directory, body: "printf '@firmdrop\\tPROGRESS\\t1\\t2\\n'; echo 'Handshake receive failed' >&2; exit 1\n")
            await #expect(throws: FlashError.commandFailed(1, "Handshake receive failed")) {
                try await FlashEngine(executable: failing).probe(device)
            }
        }
    }

    @Test func keepsDrainingAProcessThatIgnoresTerminationAfterOversizedOutput() async throws {
        let script = """
        trap '' TERM
        exec /usr/bin/perl -e 'alarm 30; exec @ARGV' /usr/bin/awk 'BEGIN { s = "A"; while (length(s) < 131072) s = s s; print s; for (i = 0; i < 20000; i++) print "output after the long line"; exit 0 }'
        """
        let start = ContinuousClock.now
        await #expect(throws: FlashError.outputTooLarge) {
            try await CommandRunner.run(URL(filePath: "/bin/sh"), arguments: ["-c", script])
        }
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func metadataCommandsHaveTimeouts() async throws {
        await #expect(throws: FlashError.timedOut) {
            try await CommandRunner.run(URL(filePath: "/bin/sleep"), arguments: ["10"], timeout: 0.1)
        }
    }

    @Test func engineRequiresSuccessAndCompletionMarker() async throws {
        try await withTemporaryDirectory { directory in
            let selected = try packages(in: directory)
            let plan = try FlashPlan(model: "SM-S931B", packages: selected, device: device, reboot: true)
            let list = "if [ \"$1\" = --list ]; then printf '@firmdrop\\tDEVICE\\t0x00100000\\t42\\t26717\\tdownload\\n'; exit 0; fi\n"
            var url = try executable(in: directory, body: list + "printf '@firmdrop\\tDONE\\n'; exit 1\n")
            await #expect(throws: (any Error).self) { try await FlashEngine(executable: url).flash(plan, onLine: { _ in }) }
            url = try executable(in: directory, body: list + "echo '100%'; exit 0\n")
            await #expect(throws: FlashError.incompleteFlash) { try await FlashEngine(executable: url).flash(plan, onLine: { _ in }) }
            url = try executable(in: directory, body: list + "printf '@firmdrop\\tDONE\\n'; exit 0\n")
            try await FlashEngine(executable: url).flash(plan, onLine: { _ in })
        }
    }

    @Test func engineRefusesReconnectedTargetBeforeLaunchingFlash() async throws {
        try await withTemporaryDirectory { directory in
            let selected = try packages(in: directory)
            let plan = try FlashPlan(model: "SM-S931B", packages: selected, device: device, reboot: true)
            let url = try executable(in: directory, body: "if [ \"$1\" = --list ]; then printf '@firmdrop\\tDEVICE\\t0x00100000\\t43\\t26717\\tdownload\\n'; exit 0; fi\nexit 99\n")
            await #expect(throws: FlashError.deviceChanged) { try await FlashEngine(executable: url).flash(plan, onLine: { _ in }) }
        }
    }

    @Test func validatesZIPMemberPathsAndDuplicates() throws {
        let valid = names.map { "firmware/" + $0 }
        #expect(try FlashImport.zipMembers(valid + ["README.txt"]) == valid)
        for bad in ["../" + names[0], "/" + names[0], "folder/*/" + names[0], "-d/" + names[0], "-x/" + names[0]] {
            #expect(throws: FlashError.invalidZIP) { try FlashImport.zipMembers([bad]) }
        }
        #expect(throws: FlashError.invalidZIP) { try FlashImport.zipMembers([names[0], "folder/" + names[0]]) }
    }

    @Test func readsDeclaredSizesOfTheSelectedMembers() throws {
        let lines = [
            "Archive:  firmware.zip",
            "  Length      Date    Time    Name",
            "---------  ---------- -----   ----",
            "30380810363  09-22-2026 07:49   firmware/\(names[0])",
            "        6  09-22-2026 07:49   firmware/x \(names[0])",
            "      512  09-22-2026 07:49   README.txt",
            "---------                     -------",
            "30380810881                     3 files",
        ]
        #expect(try FlashImport.declaredSizes(lines, of: ["firmware/" + names[0]]) == ["firmware/" + names[0]: 30380810363])
        #expect(throws: FlashError.invalidZIP) { try FlashImport.declaredSizes(lines, of: [names[1]]) }
    }

    @Test func zipWithBothCSCPackagesWaitsForAChoice() async throws {
        try await withTemporaryDirectory { directory in
            let selected = try packages(in: directory)
            let reset = directory.appending(path: "CSC_OXM_S931BOXM1AYB4_test.tar.md5")
            try Data(repeating: 0, count: 512).write(to: reset)
            let zip = directory.appending(path: "firmware.zip")
            let result = try await CommandRunner.run(URL(filePath: "/usr/bin/zip"), arguments: ["-j", zip.path] + selected.values.map(\.url.path) + [reset.path])
            try result.requireSuccess()
            let imported = try await FlashImport.extractZIP(zip, into: directory.appending(path: "output"))
            #expect(imported.packages[.csc] == nil)
            #expect(imported.cscOptions.map(\.preservesData) == [true, false])
        }
    }

    @Test func importsOnlyFirmwareMembersFromZIP() async throws {
        try await withTemporaryDirectory { directory in
            let selected = try packages(in: directory)
            let ignored = directory.appending(path: "unrelated.txt")
            try Data("ignored".utf8).write(to: ignored)
            let zip = directory.appending(path: "firmware.zip")
            let result = try await CommandRunner.run(URL(filePath: "/usr/bin/zip"), arguments: ["-j", zip.path] + selected.values.map(\.url.path) + [ignored.path])
            try result.requireSuccess()
            let output = directory.appending(path: "output")
            let imported = try await FlashImport.extractZIP(zip, into: output).packages
            #expect(imported.count == 4)
            #expect(imported[.csc]?.preservesData == true)
            #expect(!FileManager.default.fileExists(atPath: output.appending(path: "unrelated.txt").path))
            #expect(try Data(contentsOf: imported[.ap]!.url).count == 512)
        }
    }
}
