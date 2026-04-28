import Darwin
import Foundation

/// Enumerates running processes on the local machine and returns a
/// `ProcessSnapshot` per pid for which we can read executable path, argv, and
/// cwd. Processes for which any of those reads fails (typically: dead between
/// the listing and the inspection, or owned by another user with no access)
/// are silently skipped.
///
/// Implemented with `proc_listpids` + `proc_pidpath` for the easy bits, and
/// `sysctl(KERN_PROCARGS2)` for argv (the canonical macOS API for argv —
/// `proc_pidinfo` has no flavor that returns argv). Cwd comes from
/// `proc_pidinfo(PROC_PIDVNODEPATHINFO)`.
public enum ProcessScanner {
    public static func snapshot() -> [ProcessSnapshot] {
        let pids = listPids()
        var results: [ProcessSnapshot] = []
        results.reserveCapacity(pids.count)
        for pid in pids where pid > 0 {
            guard let exe = executablePath(pid: pid),
                  let argv = argv(pid: pid),
                  let cwd = cwd(pid: pid)
            else { continue }
            results.append(ProcessSnapshot(pid: pid, executablePath: exe, argv: argv, cwd: cwd))
        }
        return results
    }

    private static func listPids() -> [Int32] {
        let bufBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufBytes > 0 else { return [] }
        let count = Int(bufBytes) / MemoryLayout<Int32>.size
        var pids = [Int32](repeating: 0, count: count)
        let writtenBytes = pids.withUnsafeMutableBufferPointer { ptr -> Int32 in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, ptr.baseAddress, Int32(bufBytes))
        }
        guard writtenBytes > 0 else { return [] }
        let written = Int(writtenBytes) / MemoryLayout<Int32>.size
        return Array(pids.prefix(written))
    }

    private static func executablePath(pid: Int32) -> String? {
        let cap = Int(MAXPATHLEN)
        var buf = [CChar](repeating: 0, count: cap)
        let n = buf.withUnsafeMutableBufferPointer { ptr -> Int32 in
            proc_pidpath(pid, ptr.baseAddress, UInt32(cap))
        }
        guard n > 0 else { return nil }
        return String(cString: buf)
    }

    private static func cwd(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let n = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard n == size else { return nil }
        // pvi_cdir.vip_path is char[MAXPATHLEN]; copy as a C-string.
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { ptr -> String? in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cstr in
                let s = String(cString: cstr)
                return s.isEmpty ? nil : s
            }
        }
    }

    private static func argv(pid: Int32) -> [String]? {
        // KERN_PROCARGS2 layout: 4-byte argc, then argv[0]\0argv[1]\0..., then env.
        // We read the kernel's max-argv-size first, then the buffer for this pid.
        var sizeMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var maxArg: Int32 = 0
        var maxArgSize = MemoryLayout<Int32>.size
        if sysctl(&sizeMib, 2, &maxArg, &maxArgSize, nil, 0) != 0 || maxArg <= 0 {
            return nil
        }

        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var bufLen = Int(maxArg)
        var buf = [CChar](repeating: 0, count: bufLen)
        let ok = buf.withUnsafeMutableBufferPointer { ptr -> Bool in
            sysctl(&mib, 3, ptr.baseAddress, &bufLen, nil, 0) == 0
        }
        guard ok, bufLen >= MemoryLayout<Int32>.size else { return nil }

        return parseProcArgs2(buffer: buf, length: bufLen)
    }

    /// Parse the KERN_PROCARGS2 buffer into argv. Exposed for testing the
    /// parsing logic against synthetic buffers.
    static func parseProcArgs2(buffer: [CChar], length: Int) -> [String]? {
        guard length >= MemoryLayout<Int32>.size else { return nil }
        // Read argc from the first 4 bytes (host byte order).
        var argc: Int32 = 0
        _ = withUnsafeMutableBytes(of: &argc) { dst in
            buffer.withUnsafeBufferPointer { src in
                memcpy(dst.baseAddress, src.baseAddress, MemoryLayout<Int32>.size)
            }
        }
        guard argc > 0 else { return [] }

        // Skip the 4-byte argc, then skip the executable path (NUL-terminated),
        // then skip any padding NULs, then read argc strings.
        var i = MemoryLayout<Int32>.size
        // exec path
        while i < length && buffer[i] != 0 { i += 1 }
        // skip NUL padding between exec path and argv[0]
        while i < length && buffer[i] == 0 { i += 1 }

        var args: [String] = []
        args.reserveCapacity(Int(argc))
        for _ in 0..<argc {
            guard i < length else { break }
            let start = i
            while i < length && buffer[i] != 0 { i += 1 }
            // Read [start, i) as UTF-8.
            let count = i - start
            let s = buffer.withUnsafeBufferPointer { ptr -> String in
                let base = ptr.baseAddress!.advanced(by: start)
                let data = Data(bytes: base, count: count)
                return String(data: data, encoding: .utf8) ?? ""
            }
            args.append(s)
            if i < length { i += 1 } // skip NUL
        }
        return args
    }
}
