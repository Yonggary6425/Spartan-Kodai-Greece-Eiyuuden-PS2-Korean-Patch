# -*- coding: utf-8 -*-
r"""스파르탄 ~고대 그리스 영웅전~ (PS2 일본판 SLPM-66444) 한글패치 적용기  by Yonggary6425

사용법 (둘 중 하나):
  python patch.py "원본.iso"            -> "원본 (Korean).iso" 새로 생성 (원본은 그대로)
  python patch.py "원본.iso" "출력.iso"
  python patch.py "압축 푼 게임 폴더"     -> 그 폴더의 DATA\*.PAK 를 읽어 DATA_KOR 폴더에 한글 PAK 생성

같은 폴더의 spartan_kor.patch 파일이 필요합니다.
패치는 PAK 안의 바뀐 섹터만 덮어쓰며, 모든 파일의 크기와 위치(LBA)는 원본과 같습니다.
"""
import sys, os, struct, shutil, hashlib, zlib

SECTOR = 2048

def load_patch():
    here = os.path.dirname(os.path.abspath(__file__))
    blob = open(os.path.join(here, 'spartan_kor.patch'), 'rb').read()
    assert blob[:5] == b'SPKR1', '패치 파일이 손상되었습니다'
    n = struct.unpack('<I', blob[5:9])[0]
    d = zlib.decompress(blob[9:]); i = 0; out = []
    for _ in range(n):
        ln = d[i]; i += 1
        name = d[i:i + ln].decode(); i += ln
        size = struct.unpack('<I', d[i:i + 4])[0]; i += 4
        md5o = d[i:i + 16].hex(); md5n = d[i + 16:i + 32].hex(); i += 32
        nr = struct.unpack('<I', d[i:i + 4])[0]; i += 4
        runs = []
        for _ in range(nr):
            off, l = struct.unpack('<II', d[i:i + 8]); i += 8
            runs.append((off, d[i:i + l])); i += l
        out.append((name, size, md5o, md5n, runs))
    return out

def read_dir(f, lba, size, path, out):
    f.seek(lba * SECTOR); data = f.read(size); i = 0
    while i < len(data):
        ln = data[i]
        if ln == 0:
            i = (i // SECTOR + 1) * SECTOR; continue
        rec = data[i:i + ln]
        ext = struct.unpack('<I', rec[2:6])[0]; sz = struct.unpack('<I', rec[10:14])[0]
        flags = rec[25]; nl = rec[32]; name = rec[33:33 + nl]
        if name not in (b'\x00', b'\x01'):
            nm = name.decode('ascii', 'replace').split(';')[0]
            full = path + '/' + nm
            if flags & 2:
                read_dir(f, ext, sz, full, out)
            else:
                out[full.upper()] = (ext, sz)
        i += ln

def md5_region(f, pos, size):
    h = hashlib.md5(); f.seek(pos); left = size
    while left:
        b = f.read(min(left, 1 << 22)); h.update(b); left -= len(b)
    return h.hexdigest()

def apply(f, base, item):
    name, size, md5o, md5n, runs = item
    cur = md5_region(f, base, size)
    if cur == md5n:
        print('  이미 패치됨:', name); return True
    if cur != md5o:
        print('  [오류] 원본 파일이 다릅니다. 건너뜀:', name); return False
    for off, b in runs:
        f.seek(base + off); f.write(b)
    ok = md5_region(f, base, size) == md5n
    print('  적용:' if ok else '  [오류] 검증 실패:', name)
    return ok

def patch_iso(src, dst):
    items = load_patch()
    print('복사 중:', dst)
    shutil.copyfile(src, dst)
    good = 0
    with open(dst, 'r+b') as f:
        f.seek(16 * SECTOR); pvd = f.read(SECTOR)
        assert pvd[1:6] == b'CD001', 'ISO9660 이미지가 아닙니다'
        root = pvd[156:190]
        tbl = {}; read_dir(f, struct.unpack('<I', root[2:6])[0], struct.unpack('<I', root[10:14])[0], '', tbl)
        for it in items:
            key = '/DATA/' + it[0].upper()
            if key not in tbl or tbl[key][1] != it[1]:
                print('  [오류] ISO에서 찾을 수 없음:', it[0]); continue
            good += apply(f, tbl[key][0] * SECTOR, it)
    return good, len(items)

def patch_folder(folder):
    items = load_patch()
    data = os.path.join(folder, 'DATA') if os.path.isdir(os.path.join(folder, 'DATA')) else folder
    outd = os.path.join(os.path.dirname(data.rstrip('\\/')), 'DATA_KOR')
    os.makedirs(outd, exist_ok=True); good = 0
    for it in items:
        src = os.path.join(data, it[0]); dst = os.path.join(outd, it[0])
        if not os.path.exists(src):
            print('  [오류] 없음:', src); continue
        shutil.copyfile(src, dst)
        with open(dst, 'r+b') as f:
            good += apply(f, 0, it)
    print('한글 PAK 위치:', outd)
    return good, len(items)

def main():
    if len(sys.argv) < 2:
        print(__doc__); return
    src = sys.argv[1]
    if os.path.isdir(src):
        good, n = patch_folder(src)
    else:
        dst = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(src)[0] + ' (Korean).iso'
        good, n = patch_iso(src, dst)
    print('완료! (%d/%d 파일)' % (good, n))

if __name__ == '__main__':
    main()
