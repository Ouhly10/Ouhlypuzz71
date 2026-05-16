#!/usr/bin/env python3
# توليد ملف hash160 ثنائي للغز 71
# العنوان: 1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU
# hash160: f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8

import struct

HASH160 = "f6f5431d25bbf7b12e8add9af5e3475c44a0a5b8"
OUTPUT  = "/opt/puzzle71/puzzle71.bin"

data = bytes.fromhex(HASH160)
with open(OUTPUT, 'wb') as f:
    f.write(data)

print(f"✅ hash160 كُتب: {HASH160}")
print(f"📁 الملف: {OUTPUT}")
