import { applyBlockToAppData, getWriteBlocks } from '../codec/shx8800pro-codec'
import { addressLabel, getShx8800ProReadWriteAddresses } from '../constants/memory-map'
import type { AppData } from '../models/radio'
import { cloneAppData, createDefaultAppData } from '../models/radio'
import { ACK, asciiBytes, buildReadFrame, buildWriteFrame, hex } from './frame'
import type { RadioTransport } from '../../transport/transport'

export interface SessionProgress {
  phase: 'handshake' | 'read' | 'write' | 'verify' | 'boot' | 'done'
  address?: number
  label: string
  percent: number
}

export interface SessionOptions {
  onProgress?: (progress: SessionProgress) => void
  onLog?: (line: string) => void
  signal?: AbortSignal
  bluetoothBlockDelayMs?: number
}

export class Shx8800ProSession {
  private readonly transport: RadioTransport
  private readonly options: SessionOptions

  constructor(transport: RadioTransport, options: SessionOptions = {}) {
    this.transport = transport
    this.options = options
  }

  async readRadio() {
    this.assertNotAborted()
    await this.handshake()
    const data = createDefaultAppData()
    await this.readBlocksInto(data)
    await this.transport.write(new Uint8Array([0x45]))
    data.updatedAt = new Date().toISOString()
    this.progress('done', undefined, 100)
    return data
  }

  async writeRadio(data: AppData) {
    this.assertNotAborted()
    await this.handshake()
    if (this.transport.kind === 'bluetooth') {
      await this.writeBluetoothBlockPairs(getWriteBlocks(data))
      await this.transport.write(new Uint8Array([0x45]))
      await this.readAck('蓝牙结束写频失败：未收到 ACK', 5000).catch(() => undefined)
      this.progress('done', undefined, 100)
      return
    }
    const blocks = getWriteBlocks(data)
    for (let index = 0; index < blocks.length; index += 1) {
      this.assertNotAborted()
      const block = blocks[index]
      this.progress('write', block.address, Math.round((index / blocks.length) * 100))
      await this.writeBlock(block.address, block.payload)
    }
    await this.transport.write(new Uint8Array([0x45]))
    this.progress('done', undefined, 100)
  }

  async writeAndVerify(data: AppData) {
    await this.writeRadio(data)
    this.progress('verify', undefined, 0)
    const readBack = await this.readRadio()
    return compareAppData(data, readBack)
  }

  async writeBootImage(rgb565: Uint8Array) {
    this.assertNotAborted()
    if (rgb565.length !== 32768) throw new Error('开机图数据必须是 128×128 RGB565，也就是 32768 bytes')
    if (this.transport.kind === 'bluetooth') {
      throw new Error('蓝牙写开机图正在开发中，请使用写频线。')
    }
    const boot = new BootImageProtocol(this.transport, this.options)
    await boot.write(rgb565)
  }

  private async handshake() {
    try {
      await this.performHandshake()
    } catch (error) {
      if (this.transport.kind !== 'serial' || !this.transport.reopen) throw error
      this.log('首次握手失败，准备重开 USB 链路后重试一次')
      await this.transport.reopen()
      await this.performHandshake()
    }
  }

  private async readBlock(address: number) {
    const request = buildReadFrame(address)
    await this.transport.write(request)
    this.log(`TX READ ${addressLabel(address)} ${hex(request)}`)
    const frame = await this.readFrame(address)
    this.log(`RX ${addressLabel(address)} ${hex(frame.slice(0, 8))} ...`)
    return frame
  }

  private async readBlocksInto(data: AppData) {
    const addresses = getShx8800ProReadWriteAddresses()
    for (let index = 0; index < addresses.length; index += 1) {
      this.assertNotAborted()
      const address = addresses[index]
      this.progress('read', address, Math.round((index / addresses.length) * 100))
      const frame = await this.readBlock(address)
      applyBlockToAppData(data, address, frame)
    }
  }

  private async writeBlock(address: number, payload: Uint8Array) {
    const frame = buildWriteFrame(address, payload)
    for (let attempt = 0; attempt < 5; attempt += 1) {
      await this.transport.write(frame)
      this.log(`TX WRITE ${addressLabel(address)} ${hex(frame.slice(0, 8))} ...`)
      try {
        await this.readAck(`写入失败：${addressLabel(address)}`, 5000)
        return
      } catch {
        if (attempt >= 4) throw new Error(`写入失败：${addressLabel(address)}`)
      }
    }
    throw new Error(`写入失败：${addressLabel(address)}`)
  }

  private async writeBluetoothBlockPairs(blocks: Array<{ address: number; payload: Uint8Array }>) {
    for (let index = 0; index < blocks.length; index += 2) {
      this.assertNotAborted()
      const first = blocks[index]
      const second = blocks[index + 1]
      this.progress('write', first.address, Math.round((index / blocks.length) * 100))
      await this.writeBluetoothFrame(first.address, first.payload)
      if (second) {
        await sleep(this.bluetoothBlockDelayMs())
        this.progress('write', second.address, Math.round(((index + 1) / blocks.length) * 100))
        await this.writeBluetoothFrame(second.address, second.payload)
      }
      try {
        await this.readAck(`蓝牙写入失败：${addressLabel(first.address)}${second ? ` / ${addressLabel(second.address)}` : ''}`, 5000)
        await sleep(this.bluetoothBlockDelayMs())
      } catch {
        throw new Error(`蓝牙写入失败：${addressLabel(first.address)}${second ? ` / ${addressLabel(second.address)}` : ''}`)
      }
    }
  }

  private async writeBluetoothFrame(address: number, payload: Uint8Array) {
    const frame = buildWriteFrame(address, payload)
    this.configureBluetoothParameterPacket()
    try {
      await this.transport.write(frame)
      this.log(`TX BLE WRITE ${addressLabel(address)} ${hex(frame.slice(0, 8))} ...`)
    } finally {
      this.restoreBluetoothParameterPacket()
    }
  }

  private async readAck(message: string, timeoutMs: number) {
    const startedAt = Date.now()
    while (Date.now() - startedAt < timeoutMs) {
      const byte = await this.transport.read(1, Math.max(300, timeoutMs - (Date.now() - startedAt))).catch(() => null)
      if (!byte) continue
      this.log(`RX ${hex(byte)}`)
      if (byte[0] === ACK) return
    }
    throw new Error(message)
  }

  private async readIdent() {
    const ident = await this.transport.read(16, 5000)
    if (ident[0] === 0x01) return ident
    const bytes = Array.from(ident)
    const startedAt = Date.now()
    while (Date.now() - startedAt < 2500) {
      const next = await this.transport.read(1, 500)
      bytes.push(next[0])
      const start = bytes.findIndex((value) => value === 0x01)
      if (start >= 0 && bytes.length - start >= 16) return new Uint8Array(bytes.slice(start, start + 16))
    }
    return new Uint8Array(bytes.slice(0, 16))
  }

  private async readFrame(address: number) {
    const expectedHigh = (address >> 8) & 0xff
    const expectedLow = address & 0xff
    const deadline = Date.now() + 6000
    const window: number[] = []
    while (Date.now() < deadline) {
      const byte = await this.transport.read(1, Math.max(300, deadline - Date.now())).catch(() => null)
      if (!byte) continue
      window.push(byte[0])
      if (window.length > 4) window.shift()
      if (window.length === 4 && window[0] === 0x52 && window[1] === expectedHigh && window[2] === expectedLow && window[3] === 0x40) {
        const payload = await this.transport.read(64, Math.max(300, deadline - Date.now()))
        const frame = new Uint8Array(68)
        frame.set(window, 0)
        frame.set(payload, 4)
        return frame
      }
    }
    throw new Error(`读回地址不匹配：${addressLabel(address)}`)
  }

  private progress(phase: SessionProgress['phase'], address: number | undefined, percent: number) {
    this.options.onProgress?.({
      phase,
      address,
      percent,
      label: address === undefined ? phaseLabel(phase) : `${phaseLabel(phase)} ${addressLabel(address)}`,
    })
  }

  private log(line: string) {
    this.options.onLog?.(line)
  }

  private configureBluetoothParameterPacket() {
    const configurable = this.transport as RadioTransport & {
      configure?: (options: { packetSize?: number; writeMode?: 'with-response' | 'without-response'; interChunkDelayMs?: number }) => void
    }
    configurable.configure?.({ packetSize: 18, writeMode: 'without-response', interChunkDelayMs: 20 })
  }

  private restoreBluetoothParameterPacket() {
    const configurable = this.transport as RadioTransport & {
      configure?: (options: { packetSize?: number; writeMode?: 'with-response' | 'without-response'; interChunkDelayMs?: number }) => void
    }
    configurable.configure?.({ packetSize: 18, writeMode: 'with-response', interChunkDelayMs: 20 })
  }

  private bluetoothBlockDelayMs() {
    return this.options.bluetoothBlockDelayMs ?? 250
  }

  private async performHandshake() {
    this.transport.drain?.()
    this.progress('handshake', undefined, 0)
    await this.transport.write(asciiBytes('PROGRAMSHXPU'))
    this.log('TX PROGRAMSHXPU')
    await this.readAck('设备握手失败：未收到 ACK', 5000)
    await this.transport.write(new Uint8Array([0x46]))
    this.log('TX 46')
    const ident = await this.readIdent()
    this.log(`RX IDENT ${hex(ident)}`)
  }

  private assertNotAborted() {
    if (this.options.signal?.aborted) throw new DOMException('操作已取消', 'AbortError')
  }
}

function phaseLabel(phase: SessionProgress['phase']) {
  const labels = {
    handshake: '握手',
    read: '读频',
    write: '写频',
    verify: '校验',
    boot: '开机图',
    done: '完成',
  }
  return labels[phase]
}

export function compareAppData(expected: AppData, actual: AppData) {
  const left = JSON.stringify(stripTransient(expected))
  const right = JSON.stringify(stripTransient(actual))
  return {
    ok: left === right,
    expected: cloneAppData(expected),
    actual,
  }
}

function stripTransient(data: AppData) {
  const copy = cloneAppData(data)
  copy.updatedAt = ''
  return copy
}

const BOOT = {
  header: 0xa5,
  ackPayload: 0x59,
  cmdWrite: 0x57,
  cmdHandshake: 0x02,
  cmdSetAddress: 0x03,
  cmdErase: 0x04,
  cmdOver: 0x06,
  imageAddress: 0x00010000,
  erasePackageId: 17668,
  blockBytes: 1024,
} as const

class BootImageProtocol {
  private readonly transport: RadioTransport
  private readonly options: SessionOptions

  constructor(transport: RadioTransport, options: SessionOptions) {
    this.transport = transport
    this.options = options
  }

  async write(rgb565: Uint8Array) {
    this.transport.drain?.()
    this.progress(0, '切换开机图模式')
    await this.enterBootMode()
    await this.transport.write(new Uint8Array([0x44]))
    this.options.onLog?.('TX 44')
    await sleep(120)
    await this.transport.reopen?.()
    await sleep(180)
    this.transport.drain?.()

    await this.sendAndExpect(BOOT.cmdHandshake, 0, asciiBytes('PROGRAM'), '图片协议握手', 3)
    await this.sendAndExpect(BOOT.cmdErase, BOOT.erasePackageId, buildErasePayload(), '擦除图片区域', 8)
    await this.sendAndExpect(BOOT.cmdSetAddress, 0, buildAddressPayload(BOOT.imageAddress), '设置图片地址', 12)

    const total = Math.ceil(rgb565.length / BOOT.blockBytes)
    for (let index = 0; index < total; index += 1) {
      this.assertNotAborted()
      const chunk = new Uint8Array(BOOT.blockBytes)
      chunk.fill(0xff)
      chunk.set(rgb565.slice(index * BOOT.blockBytes, (index + 1) * BOOT.blockBytes))
      const percent = 12 + Math.round(((index + 1) / total) * 84)
      await this.sendAndExpect(BOOT.cmdWrite, index, chunk, `写入图片块 ${index + 1}/${total}`, percent)
    }

    this.progress(99, '结束图片写入')
    await this.transport.write(buildBootImagePackage(BOOT.cmdOver, 0, asciiBytes('Over')))
    await sleep(120)
    this.progress(100, '开机图完成')
  }

  private async enterBootMode() {
    const commands = ['PROGRAMSHXPU', 'PROGROMSHXU']
    for (const command of commands) {
      for (let attempt = 0; attempt < 3; attempt += 1) {
        this.assertNotAborted()
        this.transport.drain?.()
        await this.transport.write(asciiBytes(command))
        this.options.onLog?.(`TX ${command} #${attempt + 1}`)
        try {
          const ack = await this.transport.read(1, 1800)
          this.options.onLog?.(`RX ${hex(ack)}`)
          if (ack[0] === ACK) return
        } catch {
          if (attempt >= 2 && command === commands[commands.length - 1]) break
        }
        await sleep(220)
      }
    }
    throw new Error('开机图握手失败：设备没有进入刷图模式')
  }

  private async sendAndExpect(
    command: number,
    packageId: number,
    payload: Uint8Array,
    label: string,
    percent: number,
    expectedPackageId?: number,
    successStatus?: number,
  ) {
    this.progress(percent, label)
    const packet = buildBootImagePackage(command, packageId, payload)
    for (let attempt = 0; attempt < 4; attempt += 1) {
      this.assertNotAborted()
      await this.transport.write(packet)
      const response = await this.readPackage(command, command === BOOT.cmdErase ? 12000 : 6000, expectedPackageId, successStatus).catch((error) => {
        if (attempt >= 3) throw error
        return null
      })
      if (response && response.length === 1 && response[0] === BOOT.ackPayload) return
    }
    throw new Error(`${label}失败：设备未确认`)
  }

  private async readPackage(expectedCommand: number, timeoutMs: number, expectedPackageId?: number, successStatus?: number) {
    const deadline = Date.now() + timeoutMs
    const buffer: number[] = []
    const maxPayloadLength = BOOT.blockBytes

    while (Date.now() < deadline) {
      const byte = await this.transport.read(1, Math.max(150, deadline - Date.now())).catch(() => null)
      if (!byte) continue
      buffer.push(byte[0])

      while (buffer.length > 0 && buffer[0] !== BOOT.header) buffer.shift()
      if (buffer.length < 6) continue

      const length = (buffer[4] << 8) | buffer[5]
      if (length > maxPayloadLength) {
        this.options.onLog?.(`跳过异常开机图响应长度：${length}`)
        buffer.shift()
        continue
      }

      const packetLength = 6 + length + 2
      if (buffer.length < packetLength) continue

      const packet = new Uint8Array(buffer.splice(0, packetLength))
      const expectedCrc = (packet[6 + length] << 8) | packet[6 + length + 1]
      const actualCrc = crc16Ccitt(packet, 1, length + 5)
      if (expectedCrc !== actualCrc) {
        this.options.onLog?.('跳过开机图响应：CRC 校验失败')
        continue
      }

      if (packet[1] === 0xee) {
        const status = packet[6]
        if (successStatus !== undefined && status === successStatus) {
          this.options.onLog?.(`开机图状态完成：0x${status.toString(16)}`)
          return new Uint8Array([BOOT.ackPayload])
        }
        this.options.onLog?.(`跳过开机图状态包：0x${status?.toString(16) ?? '??'}`)
        continue
      }

      if (packet[1] !== expectedCommand) {
        this.options.onLog?.(`跳过开机图响应命令：0x${packet[1].toString(16)}`)
        continue
      }
      const packageId = (packet[2] << 8) | packet[3]
      if (expectedPackageId !== undefined && packageId !== expectedPackageId) {
        this.options.onLog?.(`跳过开机图响应包号：${packageId}`)
        continue
      }
      return packet.slice(6, 6 + length)
    }

    throw new Error(`开机图响应超时：0x${expectedCommand.toString(16)}`)
  }

  private progress(percent: number, label: string) {
    this.options.onProgress?.({ phase: 'boot', percent, label })
    this.options.onLog?.(label)
  }

  private assertNotAborted() {
    if (this.options.signal?.aborted) throw new DOMException('操作已取消', 'AbortError')
  }
}

export function buildBootImagePackage(command: number, packageId: number, payload: Uint8Array) {
  const packet = new Uint8Array(6 + payload.length + 2)
  packet[0] = BOOT.header
  packet[1] = command
  packet[2] = (packageId >> 8) & 0xff
  packet[3] = packageId & 0xff
  packet[4] = (payload.length >> 8) & 0xff
  packet[5] = payload.length & 0xff
  packet.set(payload, 6)
  const crc = crc16Ccitt(packet, 1, payload.length + 5)
  packet[6 + payload.length] = (crc >> 8) & 0xff
  packet[6 + payload.length + 1] = crc & 0xff
  return packet
}

export function crc16Ccitt(data: Uint8Array, offset = 0, count = data.length - offset) {
  let crc = 0
  for (let index = 0; index < count; index += 1) {
    crc ^= data[offset + index] << 8
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc & 0x8000) === 0x8000 ? (crc << 1) ^ 0x1021 : crc << 1
      crc &= 0xffff
    }
  }
  return crc
}

function buildAddressPayload(address: number) {
  return new Uint8Array([address & 0xff, (address >> 8) & 0xff, (address >> 16) & 0xff, (address >> 24) & 0xff])
}

function buildErasePayload() {
  const address = buildAddressPayload(BOOT.imageAddress)
  return new Uint8Array([...address, 0x00, 0x01])
}

function sleep(ms: number) {
  return new Promise((resolve) => globalThis.setTimeout(resolve, ms))
}
