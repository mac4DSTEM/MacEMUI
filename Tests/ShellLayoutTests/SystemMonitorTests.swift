// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEMTests/FinalPolishMTests.swift (P5b: the memory figure) and mac4DSTEMTests/PolishP2FormatTests.swift (P2ByteStyleTests)
// Changes: test class nonisolated; no assertion changed
// END MOVED FROM
//
//  The status strip's memory figure (P5b: the physical footprint, not resident_size) and the one byte style.
//  Each test names the mutation it catches.
//

import Darwin
import Foundation
import XCTest
@testable import ShellLayout

nonisolated final class SystemMonitorTests: XCTestCase {

    // MARK: - P5b: the memory figure is the physical footprint, not resident_size

    /// The old reader's quantity, as the control: `resident_size` in MiB.
    private func residentSizeMiB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : .nan
    }

    /// Mutation it catches: a reader that returns 0 / a constant, reads a quantity that ignores dirty
    /// memory, or returns the wrong UNIT (decimal MB instead of MiB: 256 MiB would read 268.4, and the
    /// strip, which converts MiB to MB at its call site, would then read 4.9 % high). A deltas test:
    /// the host's own allocations moved the figure by 0.03 MiB in the sibling test's runs, so a
    /// 10 MiB window around the 256 MiB touched is generous and still tells MiB from MB (12.4 apart).
    func testTheMemoryFigureRisesWithDirtyAnonymousPagesInMiB() throws {
        let mib = 256
        let bytes = mib << 20
        let before = SystemMonitor.residentMemoryMB()
        let base = try XCTUnwrap(mmap(nil, bytes, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0))
        XCTAssertNotEqual(base, UnsafeMutableRawPointer(bitPattern: -1), "mmap of \(mib) MiB failed")
        defer { _ = munmap(base, bytes) }
        memset(base, 0xA5, bytes)
        let after = SystemMonitor.residentMemoryMB()
        XCTAssertEqual(after - before, Double(mib), accuracy: 10,
                       "\(mib) MiB of touched anonymous memory must show as ~\(mib) in the figure (MiB, not MB): \(before) -> \(after)")
    }

    /// Mutation it catches: the old `resident_size` reader (a 300 MiB file mapping read page by page
    /// raises it by ~300 MiB, and the strip then read "23 GB" for a 16 GiB cube whose footprint was
    /// 3 GB). The control line proves the file pages DID become resident, so the test cannot pass
    /// because the mapping was never touched.
    func testTheMemoryFigureDoesNotCountCleanMappedFilePages() throws {
        let bytes = 300 << 20
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemMonitorTests-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        let chunk = Data(repeating: 0x5A, count: 1 << 20)
        for _ in 0..<(bytes >> 20) { try handle.write(contentsOf: chunk) }
        try handle.close()

        let fd = open(url.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        let footprintBefore = SystemMonitor.residentMemoryMB()
        let residentBefore = residentSizeMiB()
        let base = try XCTUnwrap(mmap(nil, bytes, PROT_READ, MAP_PRIVATE, fd, 0))
        XCTAssertNotEqual(base, UnsafeMutableRawPointer(bitPattern: -1), "mmap of the file failed")
        defer { _ = munmap(base, bytes) }
        var sum = 0
        let step = 4096
        for offset in stride(from: 0, to: bytes, by: step) {
            sum &+= Int(base.load(fromByteOffset: offset, as: UInt8.self))
        }
        XCTAssertEqual(sum, (bytes / step) * 0x5A, "every page must have been read")
        let footprintRise = SystemMonitor.residentMemoryMB() - footprintBefore
        let residentRise = residentSizeMiB() - residentBefore
        XCTAssertGreaterThan(residentRise, 200,
                             "control: resident_size must count the mapped file pages (rose \(residentRise) MiB)")
        XCTAssertLessThan(footprintRise, 50,
                          "clean mapped file pages are the page cache's, not the app's (footprint rose \(footprintRise) MiB; resident_size \(residentRise))")
    }

    // MARK: - One byte style

    func testSidebarAndSheetShareOneStyle() {
        let bytes = 15_840_000_000 + 12_345_678
        XCTAssertEqual(SystemMonitor.byteString(bytes), displayByteString(bytes))
        let small = 668_500_000
        XCTAssertEqual(SystemMonitor.byteString(small), displayByteString(small))
    }

    func testDecimalNotBinary() {
        // 1,000,000,000 bytes is 1 GB in the app's style; the binary one read "954 MB".
        XCTAssertFalse(SystemMonitor.byteString(1_000_000_000).contains("954"))
    }
}
