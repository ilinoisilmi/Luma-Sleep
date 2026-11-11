import Foundation
public struct ImportIssue: Identifiable, Sendable {
    public var row: Int
    public var message: String
    public var id: Int { row }
}
public struct ImportPreview: Sendable {
    public var accepted: [SleepRecord] = []
    public var duplicates = 0
    public var rejected: [ImportIssue] = []
    public var total: Int { accepted.count+duplicates+rejected.count }
}
public enum SleepLogFormat {
    public static let columns=["id","source_id","source_name","start","end","timezone","stage","kind"]
    public static func date(_ text: String) -> Date? {
        guard text.range(of:#"(Z|[+-]\d{2}:\d{2})$"#,options:.regularExpression) != nil else { return nil }
        let f=ISO8601DateFormatter(); f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        if let d=f.date(from:text) { return d }; f.formatOptions=[.withInternetDateTime]; return f.date(from:text)
    }
    public static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from:date) }
    /// RFC 4180 quoting, embedded newlines and CRLF, with strict malformed quote rejection.
    public static func parseCSV(_ text: String) throws -> [[String]] {
        var rows: [[String]]=[], row:[String]=[], field="", quoted=false, closed=false
        let chars=Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        var i=0
        while i<chars.count {
            let c=chars[i]
            if quoted {
                if c == "\"" {
                    if i+1<chars.count && chars[i+1] == "\"" { field.append("\""); i+=1 } else { quoted=false; closed=true }
                } else { field.append(c) }
            } else if c == "\"" {
                guard field.isEmpty && !closed else { throw LumaError.invalid("Malformed CSV quote.") }; quoted=true
            } else if c == "," { row.append(field); field=""; closed=false
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                row.append(field); rows.append(row); row=[]; field=""; closed=false
                if c == "\r" && i+1<chars.count && chars[i+1] == "\n" { i+=1 }
            } else { guard !closed else { throw LumaError.invalid("Unexpected text after closing CSV quote.") }; field.append(c) }
            i+=1
        }
        guard !quoted else { throw LumaError.invalid("Unclosed CSV quote.") }
        if !field.isEmpty || !row.isEmpty || closed { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
    public static func preview(_ data: Data, format: String, existing: [SleepRecord]) throws -> ImportPreview {
        guard data.count <= 10*1024*1024 else { throw LumaError.invalid("Import files must be at most 10 MB. Split larger files first.") }
        var dictionaries:[[String:String]]=[]
        if format.lowercased() == "csv" {
            guard let text=String(data:data,encoding:.utf8) else { throw LumaError.invalid("Use UTF-8 CSV.") }
            let rows=try parseCSV(text)
            guard let header=rows.first, header == columns else { throw LumaError.invalid("CSV header must be: \(columns.joined(separator:","))") }
            dictionaries=rows.dropFirst().map { values in
                guard values.count == columns.count else { return ["_error":"Expected \(columns.count) columns; found \(values.count)."] }
                return Dictionary(uniqueKeysWithValues:zip(columns,values))
            }
        } else {
            guard let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any], obj["formatVersion"] as? Int == 1, let values=obj["records"] as? [[String:Any]] else { throw LumaError.invalid("Expected a formatVersion 1 sleep-log JSON with a records array. Backups use Restore instead.") }
            dictionaries=values.map { v in v.compactMapValues { $0 as? String } }
        }
        guard dictionaries.count <= 20000 else { throw LumaError.invalid("Import at most 20,000 rows at a time.") }
        var preview=ImportPreview()
        var known=Dictionary(existing.map { ($0.id,$0) },uniquingKeysWith:{a,_ in a})
        func fingerprint(_ r:SleepRecord) -> String { "\(r.sourceID)|\(r.start.timeIntervalSince1970)|\(r.end.timeIntervalSince1970)|\(r.stage.rawValue)|\(r.kind.rawValue)" }
        var fingerprints=Set(existing.map(fingerprint))
        for (index,row) in dictionaries.enumerated() {
            do {
                if let error=row["_error"] { throw LumaError.invalid(error) }
                guard columns.allSatisfy({ row[$0] != nil }), let start=date(row["start"]!), let end=date(row["end"]!), let stage=SleepStage(rawValue:row["stage"]!), let kind=SleepKind(rawValue:row["kind"]!), !row["id"]!.isEmpty else { throw LumaError.invalid("Missing fields, unknown stage/kind, or ISO timestamps without an explicit offset.") }
                guard ["id","source_id","source_name"].allSatisfy({ !(row[$0] ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }) else { throw LumaError.invalid("ID, source ID and source name must not be blank.") }
                // Namespace IDs to avoid collisions with HealthKit or local diary IDs.
                let sid="file:"+row["source_id"]!
                let r=SleepRecord(id:sid+":"+row["id"]!,sourceID:sid,sourceName:row["source_name"]!,method:.file,start:start,end:end,timeZoneID:row["timezone"]!,stage:stage,kind:kind,quality:.reported)
                try r.validate()
                if let old=known[r.id] {
                    guard fingerprint(old) == fingerprint(r) else { throw LumaError.invalid("This ID already exists with different data. Use a correction or a new ID.") }
                    preview.duplicates+=1
                } else if fingerprints.contains(fingerprint(r)) { preview.duplicates+=1 }
                else { preview.accepted.append(r); known[r.id]=r; fingerprints.insert(fingerprint(r)) }
            } catch { preview.rejected.append(ImportIssue(row:index+2,message:error.localizedDescription)) }
        }
        return preview
    }
    public static func exportCSV(_ records:[SleepRecord]) -> Data {
        func quote(_ s:String) -> String { "\""+s.replacingOccurrences(of:"\"",with:"\"\"")+"\"" }
        let rows=records.map { r -> String in
            // Strip only this format's namespace, preserving reimport identity.
            let source=r.sourceID.hasPrefix("file:") ? String(r.sourceID.dropFirst(5)) : r.sourceID
            let prefix=r.sourceID+":"
            let id=r.method == .file && r.id.hasPrefix(prefix) ? String(r.id.dropFirst(prefix.count)) : r.id
            return [id,source,r.sourceName,timestamp(r.start),timestamp(r.end),r.timeZoneID,r.stage.rawValue,r.kind.rawValue].map(quote).joined(separator:",")
        }
        return Data(([columns.joined(separator:",")]+rows).joined(separator:"\r\n").utf8)
    }
    public static func exampleCSV() -> Data {
        Data((columns.joined(separator:",")+"\nnight-001,diary-export,My diary,2026-11-01T23:00:00+01:00,2026-11-02T07:30:00+01:00,Europe/Skopje,asleep,main\n").utf8)
    }
    public static func exampleJSON() -> Data {
        Data(#"{"formatVersion":1,"records":[{"id":"night-001","source_id":"diary-export","source_name":"My diary","start":"2026-11-01T23:00:00+01:00","end":"2026-11-02T07:30:00+01:00","timezone":"Europe/Skopje","stage":"asleep","kind":"main"}]}"#.utf8)
    }
}
