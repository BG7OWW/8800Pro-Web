import { SHX8800PRO } from '../core/constants/memory-map'
import { ByteQueue, type RadioTransport } from './transport'

export class WebBluetoothTransport implements RadioTransport {
  readonly kind = 'bluetooth' as const
  readonly label = '蓝牙 FFE0/FFE1'
  private device?: BluetoothDevice
  private characteristic?: BluetoothRemoteGATTCharacteristic
  private queue = new ByteQueue()
  private packetSize = 20
  private interChunkDelayMs = 25
  private writeMode: 'with-response' | 'without-response' = 'with-response'
  private connected = false
  private readonly fallbackPacketSizes = [244, 185, 128, 64, 32, 20]

  static isSupported() {
    return 'bluetooth' in navigator
  }

  async open() {
    if (!WebBluetoothTransport.isSupported()) throw new Error('当前浏览器不支持 Web Bluetooth，请使用桌面 Chrome 或 Edge。')
    this.device = await navigator.bluetooth.requestDevice({
      filters: [{ name: SHX8800PRO.bluetoothName }],
      optionalServices: [SHX8800PRO.bluetoothService],
    })
    const server = await this.device.gatt?.connect()
    if (!server) throw new Error('蓝牙 GATT 连接失败')
    const service = await server.getPrimaryService(SHX8800PRO.bluetoothService)
    this.characteristic = await service.getCharacteristic(SHX8800PRO.bluetoothCharacteristic)
    await this.characteristic.startNotifications()
    this.characteristic.addEventListener('characteristicvaluechanged', this.handleChanged)
    this.connected = true
  }

  async close() {
    if (this.characteristic) {
      this.characteristic.removeEventListener('characteristicvaluechanged', this.handleChanged)
      await this.characteristic.stopNotifications().catch(() => undefined)
    }
    this.device?.gatt?.disconnect()
    this.connected = false
    this.queue.clear()
  }

  isConnected() {
    return this.connected && Boolean((this.device?.gatt as BluetoothRemoteGATTServer & { connected?: boolean } | undefined)?.connected) && Boolean(this.characteristic)
  }

  async write(data: Uint8Array) {
    if (!this.characteristic) throw new Error('蓝牙未连接')
    let offset = 0
    while (offset < data.length) {
      const chunk = data.slice(offset, offset + this.packetSize)
      try {
        await this.writeChunk(chunk)
        offset += chunk.length
      } catch (error) {
        const reduced = this.reducePacketSize()
        if (!reduced) throw error
        continue
      }
      await sleep(this.interChunkDelayMs)
    }
  }

  read(length: number, timeoutMs?: number) {
    return this.queue.read(length, timeoutMs)
  }

  drain() {
    this.queue.clear()
  }

  setPacketSize(size: number) {
    this.packetSize = Math.max(20, Math.min(244, size))
  }

  getPacketSize() {
    return this.packetSize
  }

  configure(options: { packetSize?: number; writeMode?: 'with-response' | 'without-response'; interChunkDelayMs?: number }) {
    if (options.packetSize) this.setPacketSize(options.packetSize)
    if (options.writeMode) this.writeMode = options.writeMode
    if (options.interChunkDelayMs !== undefined) this.interChunkDelayMs = Math.max(0, Math.min(250, options.interChunkDelayMs))
  }

  private async writeChunk(chunk: Uint8Array) {
    if (!this.characteristic) throw new Error('蓝牙未连接')
    const value = toBufferSource(chunk)
    if (this.writeMode === 'without-response' && this.characteristic.writeValueWithoutResponse) {
      await this.characteristic.writeValueWithoutResponse(value)
      return
    }
    if (this.characteristic.writeValueWithResponse) {
      await this.characteristic.writeValueWithResponse(value)
      return
    }
    await this.characteristic.writeValue(value)
  }

  private reducePacketSize() {
    const next = this.fallbackPacketSizes.find((size) => size < this.packetSize)
    if (!next) return false
    this.packetSize = next
    return true
  }

  private handleChanged = (event: Event) => {
    const value = (event.target as BluetoothRemoteGATTCharacteristic).value
    if (!value) return
    this.queue.push(new Uint8Array(value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength)))
  }

}

function sleep(ms: number) {
  return new Promise((resolve) => window.setTimeout(resolve, ms))
}

function toBufferSource(bytes: Uint8Array): BufferSource {
  const copy = new Uint8Array(bytes.byteLength)
  copy.set(bytes)
  return copy.buffer as ArrayBuffer
}
