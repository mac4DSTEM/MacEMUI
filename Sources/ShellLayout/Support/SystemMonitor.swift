//
//  SystemMonitor.swift
//  Role: Lightweight process metrics for the status strip, and the two plain formatters the apps print with.
//

import Darwin
import Foundation

public nonisolated enum SystemMonitor {

    /// The memory this process is responsible for — its physical footprint
    /// (`task_vm_info.phys_footprint`, what Activity Monitor's Memory column
    /// shows) — in MiB (bytes / 2^20; the status strip's call site converts to
    /// the decimal MB `OperationMetricsFormat.glance` takes). NOT
    /// `resident_size`: that counts the memory-mapped cube's clean file pages,
    /// which the kernel may drop at any time and which belong to the page
    /// cache, so a streamed 28 GB cube read "27 GB" for a process whose
    /// footprint was 10-22 MB.
    /// The name is the frozen call site's (the status strip's `systemGlance`); it
    /// is renamed when that shell is next open. 0 when the kernel call fails.
    // The same 8 lines as `DetectorTraining.footprintMB`, copied rather than
    // shared on purpose: the training module depends on the app core alone and
    // the training probe compiles it against that alone, so it cannot call this
    // package; the 8-line copy is the smaller change.
    public static func residentMemoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Format a byte count as MB or GB.
    public static func byteString(_ bytes: Int) -> String {
        // One style app-wide: Finder's decimal one (`displayByteString`), so
        // the sidebar's "Resident" reads like the sheet's and the inspector's.
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// A count with fixed grouping rather than the user's locale, because the byte string beside it is itself
    /// unlocalized (`byteString` always formats "3.96 GB" with a period decimal point). Locale grouping would
    /// put two meanings of "." in one line (e.g. German grouping reads as a second decimal point). One
    /// convention per line.
    public static func count(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US")))
    }
}
