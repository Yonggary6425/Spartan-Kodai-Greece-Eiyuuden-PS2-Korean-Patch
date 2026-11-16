# 스파르탄 ~고대 그리스 영웅전~ (PS2 일본판 SLPM-66444) 한글패치 적용기  by Yonggary6425
# 사용법: 패치하기.bat 위에 원본 ISO(또는 압축 푼 게임 폴더)를 끌어다 놓으세요.
param([string]$Src, [string]$Dst)

$code = @"
using System;
using System.IO;
using System.IO.Compression;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;

public class SpartanKor {
    public class Item { public string Name; public uint Size; public string Md5o; public string Md5n; public List<KeyValuePair<uint, byte[]>> Runs = new List<KeyValuePair<uint, byte[]>>(); }
    public static List<string> Log = new List<string>();

    static string Hex(byte[] b, int o, int n) { var sb = new StringBuilder(); for (int i = 0; i < n; i++) sb.Append(b[o + i].ToString("x2")); return sb.ToString(); }

    public static List<Item> Load(string path) {
        byte[] f = File.ReadAllBytes(path);
        if (Encoding.ASCII.GetString(f, 0, 5) != "SPKR2") throw new Exception("bad patch file");
        int n = BitConverter.ToInt32(f, 5); int rawLen = BitConverter.ToInt32(f, 9);
        byte[] d = new byte[rawLen];
        using (var ms = new MemoryStream(f, 13, f.Length - 13))
        using (var ds = new DeflateStream(ms, CompressionMode.Decompress)) {
            int got = 0; while (got < rawLen) { int r = ds.Read(d, got, rawLen - got); if (r <= 0) break; got += r; }
            if (got != rawLen) throw new Exception("patch decompress failed");
        }
        var items = new List<Item>(); int i = 0;
        for (int k = 0; k < n; k++) {
            var it = new Item(); int ln = d[i]; i++;
            it.Name = Encoding.ASCII.GetString(d, i, ln); i += ln;
            it.Size = BitConverter.ToUInt32(d, i); i += 4;
            it.Md5o = Hex(d, i, 16); it.Md5n = Hex(d, i + 16, 16); i += 32;
            uint nr = BitConverter.ToUInt32(d, i); i += 4;
            for (uint r = 0; r < nr; r++) {
                uint off = BitConverter.ToUInt32(d, i); int l = BitConverter.ToInt32(d, i + 4); i += 8;
                byte[] b = new byte[l]; Buffer.BlockCopy(d, i, b, 0, l); i += l;
                it.Runs.Add(new KeyValuePair<uint, byte[]>(off, b));
            }
            items.Add(it);
        }
        return items;
    }

    static string Md5Region(FileStream fs, long pos, long size) {
        using (var md5 = MD5.Create()) {
            fs.Position = pos; byte[] buf = new byte[1 << 20]; long left = size;
            while (left > 0) {
                int r = fs.Read(buf, 0, (int)Math.Min(buf.Length, left));
                if (r <= 0) break;
                md5.TransformBlock(buf, 0, r, null, 0); left -= r;
            }
            md5.TransformFinalBlock(new byte[0], 0, 0);
            return Hex(md5.Hash, 0, 16);
        }
    }

    static bool Apply(FileStream fs, long bas, Item it) {
        string cur = Md5Region(fs, bas, it.Size);
        if (cur == it.Md5n) { Log.Add("  already patched: " + it.Name); return true; }
        if (cur != it.Md5o) { Log.Add("  [ERROR] original file differs, skipped: " + it.Name); return false; }
        foreach (var r in it.Runs) { fs.Position = bas + r.Key; fs.Write(r.Value, 0, r.Value.Length); }
        fs.Flush();
        bool ok = Md5Region(fs, bas, it.Size) == it.Md5n;
        Log.Add((ok ? "  patched: " : "  [ERROR] verify failed: ") + it.Name);
        return ok;
    }

    static void ReadDir(FileStream fs, uint lba, uint size, string path, Dictionary<string, uint[]> outd) {
        byte[] data = new byte[size]; fs.Position = (long)lba * 2048; fs.Read(data, 0, (int)size);
        int i = 0;
        while (i < data.Length) {
            int ln = data[i];
            if (ln == 0) { i = (i / 2048 + 1) * 2048; continue; }
            uint ext = BitConverter.ToUInt32(data, i + 2); uint sz = BitConverter.ToUInt32(data, i + 10);
            int flags = data[i + 25]; int nl = data[i + 32];
            if (!(nl == 1 && (data[i + 33] == 0 || data[i + 33] == 1))) {
                string nm = Encoding.ASCII.GetString(data, i + 33, nl).Split(';')[0];
                string full = path + "/" + nm;
                if ((flags & 2) != 0) ReadDir(fs, ext, sz, full, outd);
                else outd[full.ToUpper()] = new uint[] { ext, sz };
            }
            i += ln;
        }
    }

    public static int PatchIso(string iso, List<Item> items) {
        int good = 0;
        using (var fs = new FileStream(iso, FileMode.Open, FileAccess.ReadWrite)) {
            byte[] pvd = new byte[2048]; fs.Position = 16 * 2048; fs.Read(pvd, 0, 2048);
            if (Encoding.ASCII.GetString(pvd, 1, 5) != "CD001") throw new Exception("not an ISO9660 image");
            uint rl = BitConverter.ToUInt32(pvd, 156 + 2); uint rs = BitConverter.ToUInt32(pvd, 156 + 10);
            var tbl = new Dictionary<string, uint[]>(); ReadDir(fs, rl, rs, "", tbl);
            foreach (var it in items) {
                string key = "/DATA/" + it.Name.ToUpper();
                if (!tbl.ContainsKey(key) || tbl[key][1] != it.Size) { Log.Add("  [ERROR] not found in ISO: " + it.Name); continue; }
                if (Apply(fs, (long)tbl[key][0] * 2048, it)) good++;
            }
        }
        return good;
    }

    public static int PatchFile(string file, Item it) {
        using (var fs = new FileStream(file, FileMode.Open, FileAccess.ReadWrite)) { return Apply(fs, 0, it) ? 1 : 0; }
    }
}
"@
Add-Type -TypeDefinition $code -Language CSharp

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$patch = Join-Path $here 'spartan_kor.bin'
if (-not $Src) { Write-Host '원본 ISO 파일 또는 게임 폴더를 패치하기.bat 위에 끌어다 놓으세요.'; exit 1 }
try {
    $items = [SpartanKor]::Load($patch)
    if (Test-Path -LiteralPath $Src -PathType Container) {
        $data = Join-Path $Src 'DATA'
        if (-not (Test-Path -LiteralPath $data -PathType Container)) { $data = $Src }
        $outd = Join-Path (Split-Path -Parent $data) 'DATA_KOR'
        New-Item -ItemType Directory -Force -Path $outd | Out-Null
        $good = 0
        foreach ($it in $items) {
            $s = Join-Path $data $it.Name; $d = Join-Path $outd $it.Name
            if (-not (Test-Path -LiteralPath $s)) { Write-Host "  [오류] 없음: $s"; continue }
            Copy-Item -LiteralPath $s -Destination $d -Force
            $good += [SpartanKor]::PatchFile($d, $it)
        }
        Write-Host "한글 PAK 위치: $outd"
    } else {
        if (-not $Dst) { $Dst = Join-Path (Split-Path -Parent $Src) (([IO.Path]::GetFileNameWithoutExtension($Src)) + ' (Korean).iso') }
        Write-Host "ISO 복사 중 (1~2분 걸릴 수 있음): $Dst"
        Copy-Item -LiteralPath $Src -Destination $Dst -Force
        Write-Host '패치 적용 중...'
        $good = [SpartanKor]::PatchIso($Dst, $items)
    }
    [SpartanKor]::Log | ForEach-Object { Write-Host $_ }
    Write-Host ("완료! ({0}/{1} 파일)" -f $good, $items.Count)
} catch {
    [SpartanKor]::Log | ForEach-Object { Write-Host $_ }
    Write-Host "[오류] $($_.Exception.Message)"
    exit 1
}
