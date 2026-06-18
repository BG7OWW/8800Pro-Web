import assert from 'node:assert/strict'
import { applyBlockToAppData, encodeBlockForAddress, getBluetoothWriteBlocks } from '../src/core/codec/shx8800pro-codec'
import { encodeChannelFrequency, decodeChannelFrequency, encodeVfoFrequency, decodeVfoFrequency } from '../src/core/codec/frequency'
import { encodeRadioText, decodeRadioText } from '../src/core/codec/text'
import { encodeTone, decodeTone } from '../src/core/codec/tone'
import { getShx8800ProReadWriteAddresses, SHX8800PRO } from '../src/core/constants/memory-map'
import { cloneAppData, createDefaultAppData } from '../src/core/models/radio'
import { buildFrame, buildReadFrame, buildWriteFrame } from '../src/core/protocol/frame'
import { buildBootImagePackage, crc16Ccitt, Shx8800ProSession } from '../src/core/protocol/shx8800pro-session'
import type { RadioTransport } from '../src/transport/transport'

function roundtripAddress(address: number) {
  const source = createDefaultAppData()
  source.channels[0][0] = {
    ...source.channels[0][0],
    visible: true,
    rxFreq: '145.50000',
    txFreq: '435.50000',
    rxTone: '67.0',
    txTone: 'D023N',
    txPower: 2,
    bandwidth: 1,
    scanAdd: 1,
    busyLock: 1,
    pttid: 2,
    signalGroup: 5,
    name: '测试01',
  }
  source.channels[0][1] = {
    ...source.channels[0][1],
    visible: true,
    rxFreq: '440.62500',
    txFreq: '440.62500',
    rxTone: 'OFF',
    txTone: 'OFF',
    name: 'SAT-A',
  }
  const payload = encodeBlockForAddress(source, address)
  const target = cloneAppData(createDefaultAppData())
  applyBlockToAppData(target, address, payload)
  return { source, target, payload }
}

assert.deepEqual(Array.from(encodeChannelFrequency('145.50000')), [0x00, 0x00, 0x55, 0x14])
assert.equal(decodeChannelFrequency(encodeChannelFrequency('440.62500'), 0), '440.62500')
assert.equal(decodeVfoFrequency(encodeVfoFrequency('145.50000')), '145.50000')

assert.deepEqual(Array.from(encodeTone('OFF')), [0, 0])
assert.equal(decodeTone(encodeTone('67.0'), 0), '67.0')
assert.equal(decodeTone(encodeTone('D023N'), 0), 'D023N')

const text = encodeRadioText('区域一ABC', 12)
assert.equal(decodeRadioText(text, 0, 12), '区域一ABC')
assert.equal(decodeRadioText(encodeRadioText('区域一二三四五六', 5), 0, 5), '区域')

const channelRoundtrip = roundtripAddress(0)
assert.equal(channelRoundtrip.target.channels[0][0].rxFreq, '145.50000')
assert.equal(channelRoundtrip.target.channels[0][0].txFreq, '435.50000')
assert.equal(channelRoundtrip.target.channels[0][0].rxTone, '67.0')
assert.equal(channelRoundtrip.target.channels[0][0].txTone, 'D023N')
assert.equal(channelRoundtrip.target.channels[0][0].name, '测试01')
assert.equal(channelRoundtrip.target.channels[0][1].rxFreq, '440.62500')

const emptyChannelBlock = encodeBlockForAddress(createDefaultAppData(), 0x0880)
assert.deepEqual(Array.from(emptyChannelBlock), Array.from(new Uint8Array(64).fill(0xff)))

const rawEmptyChannelData = createDefaultAppData()
const rawEmptyChannelBlock = new Uint8Array(64).fill(0xff)
applyBlockToAppData(rawEmptyChannelData, 0x0880, rawEmptyChannelBlock)
assert.deepEqual(Array.from(encodeBlockForAddress(rawEmptyChannelData, 0x0880)), Array.from(rawEmptyChannelBlock))

const zeroEmptyChannelData = createDefaultAppData()
const zeroEmptyChannelBlock = new Uint8Array(64)
applyBlockToAppData(zeroEmptyChannelData, 0x0880, zeroEmptyChannelBlock)
assert.equal(zeroEmptyChannelData.channels[1][4].visible, false)
assert.deepEqual(Array.from(encodeBlockForAddress(zeroEmptyChannelData, 0x0880)), Array.from(new Uint8Array(64).fill(0xff)))

const pollutedChannelData = createDefaultAppData()
const pollutedChannelBlock = new Uint8Array(64).fill(0xff)
pollutedChannelBlock.set([0x57, 0x06, 0x40, 0x40], 0)
applyBlockToAppData(pollutedChannelData, 0x0640, pollutedChannelBlock)
assert.equal(pollutedChannelData.channels[0][50].visible, false)
assert.equal(pollutedChannelData.channels[0][51].visible, false)
assert.deepEqual(Array.from(encodeBlockForAddress(pollutedChannelData, 0x0640)), Array.from(new Uint8Array(64).fill(0xff)))

const headerLikeFrequencyData = createDefaultAppData()
const headerLikeFrequencyBlock = new Uint8Array(64).fill(0xff)
headerLikeFrequencyBlock.set([0x57, 0x06, 0x40, 0x40], 0)
applyBlockToAppData(headerLikeFrequencyData, 0x0600, headerLikeFrequencyBlock)
assert.equal(headerLikeFrequencyData.channels[0][48].visible, false)
assert.equal(headerLikeFrequencyData.channels[0][48].rxFreq, '')

const headerLikeSecondHalfData = createDefaultAppData()
const headerLikeSecondHalfBlock = new Uint8Array(64).fill(0xff)
headerLikeSecondHalfBlock.set([0x57, 0x07, 0xc0, 0x40], 32)
applyBlockToAppData(headerLikeSecondHalfData, 0x0780, headerLikeSecondHalfBlock)
assert.equal(headerLikeSecondHalfData.channels[0][61].visible, false)
assert.equal(headerLikeSecondHalfData.channels[0][61].rxFreq, '')

const newChannelWithoutRaw = createDefaultAppData()
newChannelWithoutRaw.channels[0][0] = {
  ...newChannelWithoutRaw.channels[0][0],
  visible: true,
  rxFreq: '145.50000',
  txFreq: '145.50000',
  signalGroup: 15,
  pttid: 3,
}
const newChannelWithoutRawBlock = encodeBlockForAddress(newChannelWithoutRaw, 0)
assert.equal(newChannelWithoutRawBlock[12], 15)
assert.equal(newChannelWithoutRawBlock[13], 3)

const vfoSource = createDefaultAppData()
vfoSource.vfos.vfoAFreq = '145.50000'
vfoSource.vfos.vfoBFreq = '440.62500'
const vfoTarget = createDefaultAppData()
applyBlockToAppData(vfoTarget, SHX8800PRO.vfoAddress, encodeBlockForAddress(vfoSource, SHX8800PRO.vfoAddress))
assert.equal(vfoTarget.vfos.vfoAFreq, '145.50000')
assert.equal(vfoTarget.vfos.vfoBFreq, '440.62500')

const functionTarget = createDefaultAppData()
const functionSource = createDefaultAppData()
functionSource.functions.callSign = 'N0CALL'
functionSource.functions.bluetoothAudioGain = 4
applyBlockToAppData(functionTarget, SHX8800PRO.functionAddress, encodeBlockForAddress(functionSource, SHX8800PRO.functionAddress))
assert.equal(functionTarget.functions.callSign, 'N0CALL')
assert.equal(functionTarget.functions.bluetoothAudioGain, 4)

assert.deepEqual(Array.from(buildReadFrame(0x9000)), [0x52, 0x90, 0x00, 0x40])
const writeFrame = buildWriteFrame(0x9000, new Uint8Array(64).fill(0xaa))
assert.equal(writeFrame.length, 68)
assert.equal(writeFrame[0], 0x57)
assert.equal(writeFrame[3], 0x40)

const bootPacket = buildBootImagePackage(0x02, 0, new TextEncoder().encode('PROGRAM'))
assert.equal(bootPacket[0], 0xa5)
assert.equal(bootPacket[1], 0x02)
assert.equal((bootPacket[4] << 8) | bootPacket[5], 7)
assert.equal((bootPacket.at(-2)! << 8) | bootPacket.at(-1)!, crc16Ccitt(bootPacket, 1, bootPacket.length - 3))

class NoisyReadTransport implements RadioTransport {
  readonly kind = 'serial' as const
  readonly label = 'test'
  private queue: number[] = [0x00, 0xff, 0x06, ...Array.from(new Uint8Array([0x01, 0x36, 0x01, 0x74, 0x04, 0x00, 0x05, 0x20, 0x02, 0x00, 0x02, 0x60, 0x00, 0x03, 0x50, 0x04]))]

  constructor(private readonly source = createDefaultAppData()) {
    this.source.bankNames[1] = '中继台'
    this.source.channels[1][0] = {
      ...this.source.channels[1][0],
      visible: true,
      rxFreq: '439.46250',
      txFreq: '434.46250',
      rxTone: '88.5',
      txTone: '88.5',
      txPower: 0,
      bandwidth: 1,
      scanAdd: 1,
      name: '深圳梧桐山',
    }
    this.source.functions.currentBankA = 1
  }

  async open() {}
  async close() {}
  drain() {}

  async write(data: Uint8Array) {
    if (data[0] !== 0x52) return
    const address = (data[1] << 8) | data[2]
    const frame = buildFrame(0x52, address, encodeBlockForAddress(this.source, address))
    this.queue.push(0x00, 0xff, ...Array.from(frame))
  }

  async read(length: number, timeoutMs = 1000) {
    const started = Date.now()
    while (this.queue.length < length) {
      if (Date.now() - started > timeoutMs) throw new Error('timeout')
      await new Promise((resolve) => setTimeout(resolve, 1))
    }
    return new Uint8Array(this.queue.splice(0, length))
  }
}

const noisyRead = await new Shx8800ProSession(new NoisyReadTransport()).readRadio()
assert.equal(noisyRead.bankNames[1], '中继台')
assert.equal(noisyRead.functions.currentBankA, 1)
assert.equal(noisyRead.channels[1][0].rxFreq, '439.46250')
assert.equal(noisyRead.channels[1][0].name, '深圳梧桐山')
assert.equal(getShx8800ProReadWriteAddresses().includes(0x0800), true)

class BluetoothWriteTransport implements RadioTransport {
  readonly kind = 'bluetooth' as const
  readonly label = 'ble-write'
  readonly writes: Uint8Array[] = []
  readonly configs: Array<{ packetSize?: number; writeMode?: 'with-response' | 'without-response'; interChunkDelayMs?: number }> = []
  ackReads = 0
  private queue: number[] = []
  private writeFrameCount = 0
  private channelPayloadsPending = 0

  async open() {}
  async close() {}
  drain() {
    this.queue = []
  }
  configure(options: { packetSize?: number; writeMode?: 'with-response' | 'without-response'; interChunkDelayMs?: number }) {
    this.configs.push(options)
  }

  async write(data: Uint8Array) {
    this.writes.push(new Uint8Array(data))
    const text = new TextDecoder('ascii').decode(data)
    if (text === 'PROGRAMSHXPU') {
      this.queue.push(0x06)
      return
    }
    if (data.length === 1 && data[0] === 0x46) {
      this.queue.push(...Array.from(new Uint8Array([0x01, 0x36, 0x01, 0x74, 0x04, 0x00, 0x05, 0x20, 0x02, 0x00, 0x02, 0x60, 0x00, 0x03, 0x50, 0x04])))
      return
    }
    if (data.length === 4 && data[0] === 0x57 && data[3] === 0x40) {
      this.channelPayloadsPending = 2
      return
    }
    if (this.channelPayloadsPending > 0 && data.length === SHX8800PRO.framePayloadBytes) {
      this.channelPayloadsPending -= 1
      if (this.channelPayloadsPending === 0) this.queue.push(0x06)
      return
    }
    if (data.length === SHX8800PRO.frameBytes && data[0] === 0x57) {
      this.writeFrameCount += 1
      const address = (data[1] << 8) | data[2]
      if (this.writeFrameCount % 2 === 0 || address === SHX8800PRO.fmAddress) this.queue.push(0x06)
      return
    }
    if (data.length === 1 && data[0] === 0x45) this.queue.push(0x06)
  }

  async read(length: number, timeoutMs = 1000) {
    const started = Date.now()
    while (this.queue.length < length) {
      if (Date.now() - started > timeoutMs) throw new Error('timeout')
      await new Promise((resolve) => setTimeout(resolve, 1))
    }
    const result = new Uint8Array(this.queue.splice(0, length))
    if (length === 1 && result[0] === 0x06) this.ackReads += 1
    return result
  }
}

const bluetoothWriteTransport = new BluetoothWriteTransport()
const bluetoothWriteData = createDefaultAppData()
bluetoothWriteData.channels[0][0] = {
  ...bluetoothWriteData.channels[0][0],
  visible: true,
  rxFreq: '145.50000',
  txFreq: '435.50000',
  name: 'BLE-1',
}
const blePayload = encodeBlockForAddress(bluetoothWriteData, 0)
assert.equal(blePayload.length, 64)
const bleBlocks = getBluetoothWriteBlocks(bluetoothWriteData)
assert.equal(bleBlocks.some((block) => block.address === 0), true)
assert.equal(bleBlocks.some((block) => block.address === 0x40), true)
await new Shx8800ProSession(bluetoothWriteTransport, { bluetoothWritePairDelayMs: 0, bluetoothAckSettleMs: 0 }).writeRadio(bluetoothWriteData)
const channelHeaderIndex = bluetoothWriteTransport.writes.findIndex((write) => write.length === 4 && write[0] === 0x57)
assert.ok(channelHeaderIndex >= 0)
assert.deepEqual(Array.from(bluetoothWriteTransport.writes[channelHeaderIndex]), [0x57, 0x00, 0x00, 0x40])
assert.deepEqual(Array.from(bluetoothWriteTransport.writes[channelHeaderIndex + 1].slice(32, 64)), Array.from(new Uint8Array(32).fill(0xff)))
assert.deepEqual(Array.from(bluetoothWriteTransport.writes[channelHeaderIndex + 2]), Array.from(new Uint8Array(64).fill(0xff)))
const streamHeaders = bluetoothWriteTransport.writes.filter((write) => write.length === 4 && write[0] === 0x57)
assert.deepEqual(streamHeaders.map((write) => (write[1] << 8) | write[2]), [0x0000, 0xa000, 0xa080, 0xa200])
const configWrites = bluetoothWriteTransport.writes.filter((write) => write.length === SHX8800PRO.frameBytes && write[0] === 0x57)
assert.deepEqual(configWrites.map((write) => (write[1] << 8) | write[2]), [0x8000, 0x9000, 0xa100, 0xb000])
const bankNameHeaderIndex = bluetoothWriteTransport.writes.findIndex((write) => write.length === 4 && write[0] === 0x57 && write[1] === 0xa2 && write[2] === 0x00)
assert.ok(bankNameHeaderIndex >= 0)
assert.deepEqual(Array.from(bluetoothWriteTransport.writes[bankNameHeaderIndex + 1]), Array.from(encodeBlockForAddress(bluetoothWriteData, 0xa200)))
assert.deepEqual(Array.from(bluetoothWriteTransport.writes[bankNameHeaderIndex + 2]), Array.from(encodeBlockForAddress(bluetoothWriteData, 0xa240)))
assert.equal(bluetoothWriteTransport.ackReads, 1 + Math.ceil(bleBlocks.length / 2))

const rawChannelData = createDefaultAppData()
const rawChannelBlock = new Uint8Array(64).fill(0xaa)
rawChannelBlock.set(encodeChannelFrequency('430.12500'), 32)
applyBlockToAppData(rawChannelData, 0, rawChannelBlock)
rawChannelData.channels[0][0] = {
  ...rawChannelData.channels[0][0],
  visible: true,
  rxFreq: '145.50000',
  txFreq: '145.50000',
}
rawChannelData.channels[0][1] = createDefaultAppData().channels[0][1]
const rawChannelBleBlock = getBluetoothWriteBlocks(rawChannelData).find((block) => block.address === 0)
assert.ok(rawChannelBleBlock)
assert.deepEqual(Array.from(rawChannelBleBlock.payload.slice(32, 64)), Array.from(rawChannelBlock.slice(32, 64)))

const rawPreserveData = createDefaultAppData()
const rawFunction = new Uint8Array(64)
rawFunction[0] = 3
rawFunction[8] = 1
rawFunction[35] = 1
applyBlockToAppData(rawPreserveData, 0x9000, rawFunction)
assert.deepEqual(Array.from(encodeBlockForAddress(rawPreserveData, 0x9000)), Array.from(rawFunction))

const rawBankNames = new Uint8Array(64).fill(0xff)
rawBankNames.set(encodeRadioText('中继台', 12), 16)
applyBlockToAppData(rawPreserveData, 0xa200, rawBankNames)
assert.equal(rawPreserveData.bankNames[0], '')
assert.equal(rawPreserveData.bankNames[1], '中继台')
assert.deepEqual(Array.from(encodeBlockForAddress(rawPreserveData, 0xa200)), Array.from(rawBankNames))
rawPreserveData.bankNames[1] = ''
assert.deepEqual(Array.from(encodeBlockForAddress(rawPreserveData, 0xa200).slice(16, 28)), Array.from(rawBankNames.slice(16, 28)))
rawPreserveData.bankNames[1] = '新区域'
assert.equal(decodeRadioText(encodeBlockForAddress(rawPreserveData, 0xa200), 16, 12), '新区域')

const rawChannelNameData = createDefaultAppData()
const rawChannelNameBlock = new Uint8Array(64).fill(0xff)
rawChannelNameBlock.set(encodeChannelFrequency('439.46250'), 0)
rawChannelNameBlock.set(encodeChannelFrequency('434.46250'), 4)
rawChannelNameBlock.set(encodeRadioText('梧桐山', 12, 0), 20)
applyBlockToAppData(rawChannelNameData, 0, rawChannelNameBlock)
assert.equal(rawChannelNameData.channels[0][0].name, '梧桐山')
rawChannelNameData.channels[0][0].name = ''
assert.deepEqual(Array.from(encodeBlockForAddress(rawChannelNameData, 0).slice(20, 32)), Array.from(rawChannelNameBlock.slice(20, 32)))
rawChannelNameData.channels[0][0].name = '新名字'
assert.equal(decodeRadioText(encodeBlockForAddress(rawChannelNameData, 0), 20, 12), '新名字')

class NoisyBootTransport implements RadioTransport {
  readonly kind: RadioTransport['kind']
  readonly label = 'boot-noise'
  readonly bootCommands: number[] = []
  readonly bootPackets: Uint8Array[] = []
  readonly sentTexts: string[] = []
  readonly configs: Array<{ packetSize?: number; writeMode?: 'with-response' | 'without-response'; interChunkDelayMs?: number }> = []
  private queue: number[] = []

  constructor(kind: RadioTransport['kind'] = 'serial', private readonly writeResponse: 'ack' | 'status-only' = 'ack') {
    this.kind = kind
  }

  async open() {}
  async close() {}
  drain() {
    this.queue = []
  }
  configure(options: { packetSize?: number; writeMode?: 'with-response' | 'without-response'; interChunkDelayMs?: number }) {
    this.configs.push(options)
  }

  async write(data: Uint8Array) {
    const text = new TextDecoder('ascii').decode(data)
    if (text === 'PROGRAMSHXPU' || text === 'PROGROMSHXU') {
      this.sentTexts.push(text)
      this.queue.push(0x06)
      return
    }
    if (data.length === 1 && data[0] === 0x44) {
      this.queue.push(0x01, 0x36, 0x01, 0x74, 0x04, 0x00, 0x05, 0x20)
      return
    }
    if (data[0] !== 0xa5) return

    const command = data[1]
    const packageId = (data[2] << 8) | data[3]
    this.bootPackets.push(new Uint8Array(data))
    this.bootCommands.push(command)
    if (command === 0x06) return

    if (command === 0x04) {
      if (this.kind === 'serial') {
        this.queue.push(...Array.from(buildBootImagePackage(command, packageId, new Uint8Array([0x59]))))
        return
      }
      this.queue.push(...Array.from(buildBootImagePackage(0xee, 0, new Uint8Array([0x04]))))
      this.queue.push(...Array.from(buildBootImagePackage(0xee, 0, new Uint8Array([0x01]))))
      return
    }
    if (command === 0x57) {
      if (this.writeResponse === 'status-only') {
        this.queue.push(...Array.from(buildBootImagePackage(0xee, 0, new Uint8Array([0x01]))))
      } else {
        this.queue.push(...Array.from(buildBootImagePackage(command, packageId, new Uint8Array([0x59]))))
      }
      return
    }
    this.queue.push(...Array.from(buildBootImagePackage(command, packageId, new Uint8Array([0x59]))))
  }

  async read(length: number, timeoutMs = 1000) {
    const started = Date.now()
    while (this.queue.length < length) {
      if (Date.now() - started > timeoutMs) throw new Error('timeout')
      await new Promise((resolve) => setTimeout(resolve, 1))
    }
    return new Uint8Array(this.queue.splice(0, length))
  }
}

const noisyBootTransport = new NoisyBootTransport('serial')
await new Shx8800ProSession(noisyBootTransport).writeBootImage(new Uint8Array(32768))
assert.equal(noisyBootTransport.sentTexts[0], 'PROGRAMSHXPU')
assert.deepEqual(noisyBootTransport.bootCommands.slice(0, 3), [0x02, 0x04, 0x03])
assert.deepEqual(Array.from(noisyBootTransport.bootPackets[1].slice(6, 12)), [0x00, 0x00, 0x01, 0x00, 0x00, 0x01])
assert.deepEqual(Array.from(noisyBootTransport.bootPackets[2].slice(6, 10)), [0x00, 0x00, 0x01, 0x00])
assert.equal(noisyBootTransport.bootCommands.filter((command) => command === 0x57).length, 32)
assert.deepEqual(Array.from(noisyBootTransport.bootPackets.at(-1)!.slice(6, 10)), [0x4f, 0x76, 0x65, 0x72])

await assert.rejects(
  () => new Shx8800ProSession(new NoisyBootTransport('bluetooth')).writeBootImage(new Uint8Array(32768)),
  /蓝牙写开机图正在开发中，请使用写频线/,
)

console.log('protocol tests passed')
