import Darwin
import Foundation

/// The process's memory as the kernel itself accounts it — the numbers jetsam
/// acts on, not "resident size". Read on demand from `task_info(TASK_VM_INFO)`;
/// nothing samples in the background.
///
/// `peak` is the kernel's own LIFETIME high-water mark
/// (`ledger_phys_footprint_peak`): it survives the memory being freed, so a
/// readout opened after a long background session shows the worst moment of
/// that session with no sampler running in the meantime (verified 2026-11-07:
/// map + touch 200 MB, unmap → footprint back to 1 MB, peak stays 201 MB).
/// A DEBUG sampler would have been exactly the periodic background wake-up
/// this readout exists to catch.
///
/// Pure Darwin + Foundation, compiled into `AppleNugsTests`.
struct MemoryFootprint: Equatable, Sendable {
    /// `phys_footprint`, bytes.
    var current: UInt64
    /// Lifetime peak of `phys_footprint`, bytes.
    var peak: UInt64
    /// Bytes left before the jetsam limit (iOS). nil where the kernel reports
    /// no limit (macOS reports 0).
    var limitRemaining: UInt64?

    /// The current process's numbers, or nil if the kernel refuses.
    static func sample() -> MemoryFootprint? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MemoryFootprint(
            current: info.phys_footprint,
            peak: UInt64(max(0, info.ledger_phys_footprint_peak)),
            limitRemaining: info.limit_bytes_remaining > 0 ? info.limit_bytes_remaining : nil)
    }

    /// "18.4 MB", "1.25 GB" — binary units labelled MB/GB the way Xcode's
    /// memory gauge and jetsam limits are quoted. Locale-independent (always a
    /// "." decimal) so a pasted readout reads the same everywhere.
    static func format(bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        if mib >= 1024 { return String(format: "%.2f GB", mib / 1024) }
        if mib >= 100 { return String(format: "%.0f MB", mib) }
        return String(format: "%.1f MB", mib)
    }
}
