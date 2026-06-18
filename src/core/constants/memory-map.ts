export const SHX8800PRO = {
  minFreqMhz: 100,
  maxFreqMhz: 520,
  channelBanks: 8,
  channelsPerBank: 64,
  channelBytes: 32,
  framePayloadBytes: 64,
  frameBytes: 68,
  bluetoothPayloadBytes: 128,
  bluetoothFrameBytes: 132,
  vfoAddress: 0x8000,
  functionAddress: 0x9000,
  dtmfStartAddress: 0xa000,
  bankNameAAddress: 0xa200,
  bankNameBAddress: 0xa240,
  fmAddress: 0xb000,
  bootImageWidth: 128,
  bootImageHeight: 128,
  serialBaudRate: 115200,
  bluetoothName: 'walkie-talkie',
  bluetoothService: '0000ffe0-0000-1000-8000-00805f9b34fb',
  bluetoothCharacteristic: '0000ffe1-0000-1000-8000-00805f9b34fb',
} as const

export function getShx8800ProReadWriteAddresses() {
  const addresses: number[] = []
  for (let address = 0; address < 0x4000; address += 64) {
    addresses.push(address)
  }
  addresses.push(0x8000)
  addresses.push(0x9000)
  for (let address = 0xa000; address <= 0xa100; address += 64) {
    addresses.push(address)
  }
  addresses.push(0xa200, 0xa240, 0xb000)
  return addresses
}

export function getShx8800ProBluetoothReadWriteAddresses() {
  const addresses: number[] = []
  for (let address = 0; address < 0x4000; address += SHX8800PRO.bluetoothPayloadBytes) {
    addresses.push(address)
  }
  addresses.push(0x8000)
  addresses.push(0x9000)
  for (let address = 0xa000; address <= 0xa100; address += SHX8800PRO.bluetoothPayloadBytes) {
    addresses.push(address)
  }
  addresses.push(0xa200, 0xb000)
  return addresses
}

export function addressLabel(address: number) {
  if (address < 0x4000) return `信道 ${Math.floor(address / 64) * 2 + 1}-${Math.floor(address / 64) * 2 + 2}`
  if (address === 0x8000) return 'VFO A/B'
  if (address === 0x9000) return '功能设置'
  if (address >= 0xa000 && address <= 0xa100) return 'DTMF'
  if (address === 0xa200 || address === 0xa240) return '区域名称'
  if (address === 0xb000) return 'FM 收音机'
  return `0x${address.toString(16).toUpperCase()}`
}
