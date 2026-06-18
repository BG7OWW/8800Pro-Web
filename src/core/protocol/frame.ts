export const ACK = 0x06

export function asciiBytes(value: string) {
  return new TextEncoder().encode(value)
}

export function buildFrame(command: number, address: number, payload: Uint8Array, length = 64) {
  const frame = new Uint8Array(68)
  frame[0] = command
  frame[1] = (address >> 8) & 0xff
  frame[2] = address & 0xff
  frame[3] = length
  frame.set(payload.slice(0, length), 4)
  return frame
}

export function buildReadFrame(address: number) {
  return new Uint8Array([0x52, (address >> 8) & 0xff, address & 0xff, 64])
}

export function buildWriteFrame(address: number, payload: Uint8Array) {
  return buildFrame(0x57, address, payload, 64)
}

export function hex(bytes: Uint8Array) {
  return Array.from(bytes, (value) => value.toString(16).padStart(2, '0').toUpperCase()).join(' ')
}
