import { DTMF_CHOICES } from '../constants/choices'
import { SHX8800PRO, getShx8800ProReadWriteAddresses } from '../constants/memory-map'
import type { AppData, Channel, VfoInfos } from '../models/radio'
import { createEmptyChannel } from '../models/radio'
import {
  decodeChannelFrequency,
  decodeFmFrequency,
  decodeOffset,
  decodeVfoFrequency,
  encodeChannelFrequency,
  encodeFmFrequency,
  encodeOffset,
  encodeVfoFrequency,
} from './frequency'
import { decodeRadioText, encodeCallSign, encodeRadioText } from './text'
import { decodeTone, encodeTone } from './tone'

const DTMF_CHARS = '0123456789ABCD*#'

export function encodeBlockForAddress(data: AppData, address: number) {
  if (address < 0x4000) {
    const hasRaw = hasRawBlock(data, address)
    const payload = getBasePayload(data, address, 0xff)
    const firstChannelIndex = Math.floor(address / 64) * 2
    payload.set(encodeChannel(data.channels[Math.floor(firstChannelIndex / 64)][firstChannelIndex % 64], payload.slice(0, 32), hasRaw, address), 0)
    payload.set(encodeChannel(data.channels[Math.floor((firstChannelIndex + 1) / 64)][(firstChannelIndex + 1) % 64], payload.slice(32, 64), hasRaw), 32)
    return payload
  }

  const payload = getBasePayload(data, address)

  if (address === SHX8800PRO.vfoAddress) {
    payload.set(encodeVfo(data.vfos, 'A', payload.slice(0, 32)), 0)
    payload.set(encodeVfo(data.vfos, 'B', payload.slice(32, 64)), 32)
    return payload
  }

  if (address === SHX8800PRO.functionAddress) {
    const settings = data.functions
    payload[0] = settings.sql
    payload[1] = settings.saveMode
    payload[2] = settings.vox
    payload[3] = settings.backlight
    payload[4] = settings.dualStandby
    payload[5] = settings.tot
    payload[6] = settings.beep
    payload[7] = settings.voice
    payload[9] = settings.sideTone
    payload[10] = settings.scanMode
    payload[11] = data.vfos.pttid
    payload[12] = settings.pttDelay
    payload[13] = settings.chADisplay
    payload[14] = settings.chBDisplay
    payload[16] = settings.autoLock
    payload[17] = settings.alarmMode
    payload[18] = settings.localSosTone
    payload[20] = settings.tailClear
    payload[21] = settings.rptTailClear
    payload[22] = settings.rptTailDetect
    payload[23] = settings.roger
    payload[25] = settings.fmEnable
    payload[26] = settings.chAWorkmode | (settings.chBWorkmode << 4)
    payload[27] = settings.keyLock
    payload[28] = settings.powerOnDisplay
    payload[30] = settings.tone
    payload[32] = settings.voxDelay
    payload[33] = settings.menuQuitTime
    payload[34] = settings.micGain
    payload[36] = settings.powerOnDelay
    payload[37] = settings.voxSwitch
    payload[42] = settings.key2Short
    payload[43] = settings.key2Long
    payload[46] = settings.currentBankA
    payload[47] = settings.currentBankB
    payload[49] = settings.bluetoothMicGain
    payload[50] = settings.bluetoothAudioGain
    payload.fill(0, 52, 58)
    payload.set(encodeRadioText(encodeCallSign(settings.callSign), 6, 0), 52)
    return payload
  }

  if (address >= 0xa000 && address <= 0xa100) return encodeDtmfBlock(data, address, payload)

  if (address === SHX8800PRO.bankNameAAddress || address === SHX8800PRO.bankNameBAddress) {
    const start = address === SHX8800PRO.bankNameAAddress ? 0 : 4
    payload.fill(0xff)
    for (let index = 0; index < 4; index += 1) {
      payload.set(encodeRadioText(data.bankNames[start + index], 12), index * 16)
    }
    return payload
  }

  if (address === SHX8800PRO.fmAddress) {
    payload.set(encodeFmFrequency(data.fm.currentFreq), 0)
    data.fm.channels.forEach((freq, index) => payload.set(encodeFmFrequency(freq), 2 + index * 2))
    return payload
  }

  return payload
}

export function applyBlockToAppData(data: AppData, address: number, frame: Uint8Array) {
  const payload = frame.length === 68 ? frame.slice(4) : frame
  data.rawBlocks ??= {}
  data.rawBlocks[toBlockKey(address)] = Array.from(payload)
  if (address < 0x4000) {
    const firstChannelIndex = Math.floor(address / 64) * 2
    setChannelByFlatIndex(data, firstChannelIndex, decodeChannel(payload.slice(0, 32), (firstChannelIndex % 64) + 1, address))
    setChannelByFlatIndex(data, firstChannelIndex + 1, decodeChannel(payload.slice(32, 64), ((firstChannelIndex + 1) % 64) + 1))
    return
  }

  if (address === SHX8800PRO.vfoAddress) {
    decodeVfo(data.vfos, payload.slice(0, 32), 'A')
    decodeVfo(data.vfos, payload.slice(32, 64), 'B')
    return
  }

  if (address === SHX8800PRO.functionAddress) {
    const settings = data.functions
    settings.sql = payload[0] % 10
    settings.saveMode = payload[1] % 4
    settings.vox = payload[2] % 10
    settings.backlight = payload[3] % 9
    settings.dualStandby = payload[4] % 2
    settings.tot = payload[5] % 9
    settings.beep = payload[6] % 2
    settings.voice = payload[7] % 2
    settings.sideTone = payload[9] % 4
    settings.scanMode = payload[10] % 3
    data.vfos.pttid = payload[11] % 4
    settings.pttDelay = payload[12] % 16
    settings.chADisplay = payload[13] % 3
    settings.chBDisplay = payload[14] % 3
    settings.autoLock = payload[16] % 7
    settings.alarmMode = payload[17] % 3
    settings.localSosTone = payload[18] % 2
    settings.tailClear = payload[20] % 2
    settings.rptTailClear = payload[21] % 11
    settings.rptTailDetect = payload[22] % 11
    settings.roger = payload[23] % 2
    settings.fmEnable = payload[25] % 2
    settings.chAWorkmode = (payload[26] & 0x0f) % 2
    settings.chBWorkmode = ((payload[26] & 0xf0) >> 4) % 2
    settings.keyLock = payload[27] % 2
    settings.powerOnDisplay = payload[28] % 22
    settings.tone = payload[30] % 4
    settings.voxDelay = payload[32] % 16
    settings.menuQuitTime = payload[33] % 11
    settings.micGain = payload[34] % 3
    settings.powerOnDelay = payload[36] % 15
    settings.voxSwitch = payload[37] % 2
    settings.key2Short = payload[42] % 5
    settings.key2Long = payload[43] % 5
    settings.currentBankA = payload[46] % 8
    settings.currentBankB = payload[47] % 8
    settings.bluetoothMicGain = payload[49] % 5
    settings.bluetoothAudioGain = payload[50] % 5
    settings.callSign = decodeRadioText(payload, 52, 6)
    return
  }

  if (address >= 0xa000 && address <= 0xa100) {
    decodeDtmfBlock(data, address, payload)
    return
  }

  if (address === SHX8800PRO.bankNameAAddress || address === SHX8800PRO.bankNameBAddress) {
    const start = address === SHX8800PRO.bankNameAAddress ? 0 : 4
    for (let index = 0; index < 4; index += 1) {
      data.bankNames[start + index] = decodeRadioText(payload, index * 16, 12)
    }
    return
  }

  if (address === SHX8800PRO.fmAddress) {
    data.fm.currentFreq = decodeFmFrequency(payload, 0)
    for (let index = 0; index < 30; index += 1) {
      data.fm.channels[index] = decodeFmFrequency(payload, 2 + index * 2)
    }
  }
}

export function getWriteBlocks(data: AppData) {
  return getShx8800ProReadWriteAddresses().map((address) => ({
    address,
    payload: encodeBlockForAddress(data, address),
  }))
}

function getBasePayload(data: AppData, address: number, fillValue = 0x00) {
  const raw = data.rawBlocks?.[toBlockKey(address)]
  if (raw?.length === SHX8800PRO.framePayloadBytes) return Uint8Array.from(raw)
  return new Uint8Array(SHX8800PRO.framePayloadBytes).fill(fillValue)
}

function hasRawBlock(data: AppData, address: number) {
  return data.rawBlocks?.[toBlockKey(address)]?.length === SHX8800PRO.framePayloadBytes
}

function toBlockKey(address: number) {
  return address.toString(16).toUpperCase().padStart(4, '0')
}

function encodeChannel(channel: Channel, base?: Uint8Array, preserveUnknownFlags = Boolean(base), blockAddress?: number) {
  const baseIsUsable = Boolean(base) && !isBleFrameHeaderPollutedChannel(base!, blockAddress)
  const payload = baseIsUsable && base ? new Uint8Array(base) : new Uint8Array(32)
  if (!baseIsUsable) payload.fill(0xff)
  if (!channel.rxFreq) return new Uint8Array(32).fill(0xff)
  payload.set(encodeChannelFrequency(channel.rxFreq), 0)
  payload.set(encodeChannelFrequency(channel.txFreq || channel.rxFreq), 4)
  payload.set(encodeTone(channel.rxTone), 8)
  payload.set(encodeTone(channel.txTone), 10)
  if (!baseIsUsable || !preserveUnknownFlags || payload[12] % 20 !== channel.signalGroup) payload[12] = channel.signalGroup
  if (!baseIsUsable || !preserveUnknownFlags || payload[13] % 4 !== channel.pttid) payload[13] = channel.pttid
  payload[14] = channel.txPower
  payload[15] = (baseIsUsable && preserveUnknownFlags ? payload[15] & 0x03 : 0) | (channel.bandwidth << 6) | (channel.busyLock << 3) | (channel.scanAdd << 2)
  payload.set(encodeRadioText(channel.name, 12), 20)
  return payload
}

function decodeChannel(payload: Uint8Array, id: number, blockAddress?: number): Channel {
  if (payload[0] === 0xff || payload[1] === 0xff || payload[3] === 0 || isBleFrameHeaderPollutedChannel(payload, blockAddress)) return createEmptyChannel(id)
  const name = payload[20] !== 0xff ? decodeRadioText(payload, 20, 12) : ''
  return {
    id,
    rxFreq: decodeChannelFrequency(payload, 0),
    txFreq: payload[4] !== 0xff && payload[5] !== 0xff ? decodeChannelFrequency(payload, 4) : '',
    rxTone: decodeTone(payload, 8),
    txTone: decodeTone(payload, 10),
    signalGroup: payload[12] % 20,
    pttid: payload[13] % 4,
    txPower: payload[14] % 3,
    bandwidth: (payload[15] >> 6) & 1,
    busyLock: (payload[15] >> 3) & 1,
    scanAdd: (payload[15] >> 2) & 1,
    name,
    visible: true,
  }
}

function isBleFrameHeaderPollutedChannel(payload: Uint8Array, blockAddress?: number) {
  return (
    blockAddress !== undefined &&
    payload.length >= 4 &&
    payload[0] === 0x57 &&
    payload[1] === ((blockAddress >> 8) & 0xff) &&
    payload[2] === (blockAddress & 0xff) &&
    payload[3] === 0x40
  )
}

function setChannelByFlatIndex(data: AppData, flatIndex: number, channel: Channel) {
  const bank = Math.floor(flatIndex / SHX8800PRO.channelsPerBank)
  const index = flatIndex % SHX8800PRO.channelsPerBank
  data.channels[bank][index] = channel
}

function encodeVfo(vfo: VfoInfos, side: 'A' | 'B', base?: Uint8Array) {
  const payload = base ? new Uint8Array(base) : new Uint8Array(32)
  if (!base) {
    payload.fill(0xff)
    payload[17] = 0
    payload[18] = 0
    payload[19] = 0
    payload[20] = 0
    payload[21] = 0
    payload[22] = 0
  }
  payload.set(encodeVfoFrequency(side === 'A' ? vfo.vfoAFreq : vfo.vfoBFreq), 0)
  payload.set(encodeTone(side === 'A' ? vfo.vfoARxTone : vfo.vfoBRxTone), 8)
  payload.set(encodeTone(side === 'A' ? vfo.vfoATxTone : vfo.vfoBTxTone), 10)
  payload[13] = side === 'A' ? vfo.vfoABusyLock : vfo.vfoBBusyLock
  payload[14] =
    ((side === 'A' ? vfo.vfoADirection : vfo.vfoBDirection) << 4) |
    (side === 'A' ? vfo.vfoASignalGroup : vfo.vfoBSignalGroup)
  payload[16] = side === 'A' ? vfo.vfoATxPower : vfo.vfoBTxPower
  payload[17] = (side === 'A' ? vfo.vfoABandwidth : vfo.vfoBBandwidth) << 6
  payload[19] = side === 'A' ? vfo.vfoAStep : vfo.vfoBStep
  payload.set(encodeOffset(side === 'A' ? vfo.vfoAOffset : vfo.vfoBOffset), 20)
  return payload
}

function decodeVfo(vfo: VfoInfos, payload: Uint8Array, side: 'A' | 'B') {
  if (side === 'A') {
    vfo.vfoAFreq = decodeVfoFrequency(payload)
    vfo.vfoARxTone = decodeTone(payload, 8)
    vfo.vfoATxTone = decodeTone(payload, 10)
    vfo.vfoABusyLock = payload[13] % 2
    vfo.vfoASignalGroup = (payload[14] & 0x0f) % 16
    vfo.vfoADirection = ((payload[14] >> 4) & 3) % 3
    vfo.vfoATxPower = (payload[16] & 0x0f) % 3
    vfo.vfoAScramble = ((payload[16] >> 4) & 0x0f) % 9
    vfo.vfoABandwidth = (payload[17] >> 6) & 1
    vfo.vfoAStep = payload[19] % 8
    vfo.vfoAOffset = decodeOffset(payload, 20)
  } else {
    vfo.vfoBFreq = decodeVfoFrequency(payload)
    vfo.vfoBRxTone = decodeTone(payload, 8)
    vfo.vfoBTxTone = decodeTone(payload, 10)
    vfo.vfoBBusyLock = payload[13] % 2
    vfo.vfoBSignalGroup = (payload[14] & 0x0f) % 16
    vfo.vfoBDirection = ((payload[14] >> 4) & 3) % 3
    vfo.vfoBTxPower = (payload[16] & 0x0f) % 3
    vfo.vfoBScramble = ((payload[16] >> 4) & 0x0f) % 9
    vfo.vfoBBandwidth = (payload[17] >> 6) & 1
    vfo.vfoBStep = payload[19] % 8
    vfo.vfoBOffset = decodeOffset(payload, 20)
  }
}

function encodeDtmfBlock(data: AppData, address: number, base?: Uint8Array) {
  const payload = base ? new Uint8Array(base) : new Uint8Array(64)
  if (!base) payload.fill(0xff)
  const writeWord = (offset: number, word: string) => {
    for (let index = 0; index < Math.min(6, word.length); index += 1) {
      const charIndex = DTMF_CHARS.indexOf(word[index].toUpperCase())
      if (charIndex >= 0) payload[offset + index] = charIndex
    }
  }
  switch (address) {
    case 0xa000:
      writeWord(0, data.dtmf.localId)
      if (!base) payload[5] = 0xff
      payload[6] = data.dtmf.pttid
      payload[7] = data.dtmf.wordTime
      payload[8] = data.dtmf.idleTime
      writeWord(32, data.dtmf.groups[0])
      writeWord(48, data.dtmf.groups[1])
      break
    case 0xa040:
      ;[2, 3, 4, 5].forEach((group, index) => writeWord(index * 16, data.dtmf.groups[group]))
      break
    case 0xa080:
      ;[6, 7, 8, 9].forEach((group, index) => writeWord(index * 16, data.dtmf.groups[group]))
      break
    case 0xa0c0:
      ;[10, 11, 12, 13].forEach((group, index) => writeWord(index * 16, data.dtmf.groups[group]))
      break
    case 0xa100:
      writeWord(0, data.dtmf.groups[14])
      break
  }
  return payload
}

function decodeDtmfBlock(data: AppData, address: number, payload: Uint8Array) {
  const readWord = (offset: number) => {
    let text = ''
    for (let index = 0; index < 6 && payload[offset + index] !== 0xff; index += 1) {
      text += DTMF_CHARS[payload[offset + index] % 16]
    }
    return text
  }
  switch (address) {
    case 0xa000:
      data.dtmf.localId = readWord(0)
      data.dtmf.pttid = payload[6] % DTMF_CHOICES.sendId.length
      data.dtmf.wordTime = payload[7] % DTMF_CHOICES.time.length
      data.dtmf.idleTime = payload[8] % DTMF_CHOICES.time.length
      data.dtmf.groups[0] = readWord(32)
      data.dtmf.groups[1] = readWord(48)
      break
    case 0xa040:
      ;[2, 3, 4, 5].forEach((group, index) => (data.dtmf.groups[group] = readWord(index * 16)))
      break
    case 0xa080:
      ;[6, 7, 8, 9].forEach((group, index) => (data.dtmf.groups[group] = readWord(index * 16)))
      break
    case 0xa0c0:
      ;[10, 11, 12, 13].forEach((group, index) => (data.dtmf.groups[group] = readWord(index * 16)))
      break
    case 0xa100:
      data.dtmf.groups[14] = readWord(0)
      break
  }
}
