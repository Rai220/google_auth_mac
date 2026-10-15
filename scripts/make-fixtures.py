#!/usr/bin/env python3
"""Public synthetic fixtures; no real credentials. Independent protobuf wire encoder."""
from pathlib import Path
import base64, urllib.parse, hmac, hashlib, struct, sys
check_only = "--check" in sys.argv
root = Path(__file__).resolve().parents[1] / 'Tests/AuthenticatorCoreTests/Fixtures'
root.mkdir(parents=True, exist_ok=True)
def varint(n):
    out = bytearray()
    while n > 127:
        out.append((n & 127) | 128); n >>= 7
    return bytes(out + bytes([n]))
def num(tag, n): return varint(tag << 3) + varint(n)
def blob(tag, value):
    value = value.encode() if isinstance(value,str) else value
    return varint((tag << 3) | 2) + varint(len(value)) + value
a = blob(1,b'12345678901234567890') + blob(2,'Google:alice@example.com') + blob(3,'Google') + num(4,1) + num(5,1) + num(6,2)
b = blob(1,b'12345678901234567890123456789012') + blob(2,'bob') + blob(3,'GitHub') + num(4,2) + num(5,2) + num(6,1) + num(7,42)
def write(name, accounts, size=1, index=0, version=1, batch_id=987654):
    payload = b''.join(blob(1,a) for a in accounts) + num(2,version) + num(3,size) + num(4,index) + (num(5,batch_id) if batch_id is not None else b'')
    uri = 'otpauth-migration://offline?data=' + urllib.parse.quote(base64.b64encode(payload).decode(),safe='')
    expected = uri + '\n'
    if check_only:
        if (root/name).read_text() != expected:
            raise SystemExit(f'Synthetic fixture mismatch: {name}')
    else:
        (root/name).write_text(expected)
write('migration.txt',[a,b])
write('batch-1.txt',[a],2,0)
write('batch-2.txt',[b],2,1)
write('unsupported.txt',[a],version=99)
write('v2-1.txt',[a+blob(8,'public-test-id-a')],2,0,version=2,batch_id=None)
write('v2-2.txt',[b+blob(8,'public-test-id-b')],2,1,version=2,batch_id=None)
empty_name = blob(1,b'12345678901234567890') + blob(2,'') + blob(3,'Example') + num(4,1) + num(5,1) + num(6,2) + blob(8,'public-test-id')
write('v2-empty-name.txt',[empty_name],version=2,batch_id=None)
write('invalid-batch.txt',[a],size=2,index=2)
h = hmac.new(b'12345678901234567890123456789012',struct.pack('>Q',42),hashlib.sha256).digest()
o = h[-1] & 15
print('Independent HOTP SHA256 fixture:', f'{(int.from_bytes(h[o:o+4],"big")&0x7fffffff)%100000000:08d}')
