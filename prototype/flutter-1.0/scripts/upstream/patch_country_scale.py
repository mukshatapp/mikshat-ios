"""Apply the reviewed DataHeader::GetScaleRange Country minimum10->9 and rectangular-read detail policy.
Exact upstream binaries are SHA-guarded; every other native byte is preserved.
"""
from pathlib import Path
import hashlib,json,struct,argparse
ROOT=Path(__file__).resolve().parents[2]
POLICIES={
 'arm64-v8a':{'sha256':'de70f3498c383c958aafc190d971aa1aa877448e9326c5aa5d56ca6101e551a5','offset':0xb18afc,'before':bytes.fromhex('4b018052'),'after':bytes.fromhex('2b018052'),'extra':[(0xb19214,bytes.fromhex('48018052'),bytes.fromhex('28018052')),(0xb1b898,bytes.fromhex('f903032a'),bytes.fromhex('79100011'))]},
 'x86':{'sha256':'520088acff20dca12e80bd5b32242ec60b271a9a85885d85e158dadfdf55fd69','offset':0x1064a0,'before':struct.pack('<ii',10,17),'after':struct.pack('<ii',9,17),'extra':[(0xbd873f,bytes.fromhex('0a'),bytes.fromhex('09')),(0xbdb302,bytes.fromhex('8b4d0c39c1'),b'\xe8'+struct.pack('<i',0xbd7fc7-(0xbdb302+5))),(0xbd7fc7,b'\xcc'*9,bytes.fromhex('8b4d0c83c10439c1c3'))]},
}
def patch(base):
 results=[]
 for abi,p in POLICIES.items():
  file=base/abi/'liborganicmaps.so';data=file.read_bytes();off=p['offset'];original=bytearray(data);edits=[(off,p['before'],p['after'])]+p['extra']
  for address,before,after in edits:
   assert data[address:address+len(before)] in (before,after),f'Unexpected patch context:{abi}:{address:x}'
   original[address:address+len(before)]=before
  original=bytes(original)
  assert hashlib.sha256(original).hexdigest()==p['sha256'],f'Unrecognized native baseline: {abi}'
  assert data[off:off+len(p['before'])] in (p['before'],p['after']),abi
  if abi=='arm64-v8a':
   assert struct.unpack_from('<I',original,off)[0]==0x5280014b
   assert original[0xb18b20:0xb18b28]==bytes.fromhex('000109aac0035fd6')
  else:
   assert original[0xbd7f88:0xbd7f94]==bytes.fromhex('0fb61285d2741683fa017522')
   got=0xbd7f7b+struct.unpack_from('<i',original,0xbd7f7e)[0]
   assert got+struct.unpack_from('<i',original,0xbd7fba)[0]==off
   assert struct.unpack_from('<ii',original,got+struct.unpack_from('<i',original,0xbd7f98)[0])==(0,17)
   assert struct.unpack_from('<ii',original,got+struct.unpack_from('<i',original,0xbd7fa9)[0])==(0,9)
  updated=bytearray(original)
  for address,before,after in edits:updated[address:address+len(before)]=after
  updated=bytes(updated)
  changed=[i for i,(a,b) in enumerate(zip(original,updated)) if a!=b]
  assert changed and all(any(address<=i<address+len(before) for address,before,after in edits) for i in changed),abi
  if data!=updated:file.write_bytes(updated)
  results.append({'abi':abi,'source_sha256':p['sha256'],'patched_sha256':hashlib.sha256(updated).hexdigest(),'changed_byte_offset':hex(off),'changed_bytes':len(changed),'patch_ranges':[{'offset':hex(a),'before':b.hex(),'after':c.hex()} for a,b,c in edits],'rectangular_index_detail_boost':4,'country_min_draw_scale':9,'world_max_draw_scale':9,'upper_data_scale':17})
 return results
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--lib-dir',type=Path,default=ROOT/'decoded/lib');args=p.parse_args();print(json.dumps(patch(args.lib_dir),indent=2))
