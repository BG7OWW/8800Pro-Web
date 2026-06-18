import CoreBluetooth
import Foundation

struct MemoryFrame: Codable {
  let address: Int
  let payload: [UInt8]
}

struct MemoryFile: Codable {
  let generatedAt: String?
  let source: String?
  let frames: [MemoryFrame]
}

enum TransferMode {
  case dump(String)
  case write(String, verify: Bool)
}

final class BleMemoryTransfer: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  private let serviceUUID = CBUUID(string: "FFE0")
  private let dataUUID = CBUUID(string: "FFE1")
  private let mode: TransferMode
  private var central: CBCentralManager!
  private var peripheral: CBPeripheral?
  private var characteristic: CBCharacteristic?
  private var rxBuffer: [UInt8] = []
  private var step = 0
  private var readIndex = 0
  private var writeIndex = 0
  private var dumpFrames: [MemoryFrame] = []
  private var writeFrames: [MemoryFrame] = []
  private var timer: Timer?
  private var started = false
  private let splitWrite: Bool
  private let streamPairWrite: Bool
  private let targetName: String

  init(mode: TransferMode, splitWrite: Bool, streamPairWrite: Bool, targetName: String) {
    self.mode = mode
    self.splitWrite = splitWrite
    self.streamPairWrite = streamPairWrite
    self.targetName = targetName
    super.init()
    central = CBCentralManager(delegate: self, queue: .main)
    timer = Timer.scheduledTimer(withTimeInterval: 240, repeats: false) { _ in
      print("TIMEOUT")
      CFRunLoopStop(CFRunLoopGetMain())
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    print("central state: \(central.state.rawValue)")
    guard central.state == .poweredOn else { return }
    central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
    let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
    print("found \(name) \(peripheral.identifier) RSSI \(RSSI)")
    guard targetName.isEmpty || name.localizedCaseInsensitiveContains(targetName) else { return }
    self.peripheral = peripheral
    central.stopScan()
    peripheral.delegate = self
    central.connect(peripheral)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("connected \(peripheral.name ?? peripheral.identifier.uuidString)")
    peripheral.discoverServices(nil)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let error { print("services error \(error)") }
    for service in peripheral.services ?? [] {
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if let error { print("chars error \(error)") }
    for char in service.characteristics ?? [] {
      print("char \(char.uuid) props \(props(char.properties))")
      if char.uuid == dataUUID {
        characteristic = char
        peripheral.setNotifyValue(true, for: char)
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    if let error { print("notify error \(error)") }
    print("notify \(characteristic.uuid): \(characteristic.isNotifying)")
    guard !started else { return }
    started = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      self.startHandshake()
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    if let error {
      print("write error \(characteristic.uuid): \(error)")
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    if let error { print("rx error \(error)") }
    guard let data = characteristic.value else { return }
    let bytes = [UInt8](data)
    rxBuffer.append(contentsOf: bytes)
    pump()
  }

  private func startHandshake() {
    step = 1
    rxBuffer.removeAll()
    send(Array("PROGRAMSHXPU".utf8), label: "PROGRAMSHXPU")
  }

  private func pump() {
    if step == 1, rxBuffer.contains(0x06) {
      step = 2
      rxBuffer.removeAll()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.send([0x46], label: "46") }
      return
    }

    if step == 2, rxBuffer.count >= 16 {
      print("IDENT \(hex(Array(rxBuffer.prefix(16))))")
      rxBuffer.removeAll()
      switch mode {
      case .dump:
        readIndex = 0
        readNextDump()
      case .write(let path, _):
        loadWritePlan(path)
        writeIndex = 0
        writeNextPair()
      }
      return
    }

    if step == 3 {
      guard readIndex < readAddresses.count else { return }
      let address = readAddresses[readIndex]
      if let payload = extractPayload(address: address) {
        dumpFrames.append(MemoryFrame(address: address, payload: payload))
        if readIndex % 32 == 0 || readIndex == readAddresses.count - 1 {
          print("READ \(readIndex + 1)/\(readAddresses.count) \(addrHex(address))")
        }
        readIndex += 1
        rxBuffer.removeAll()
        if readIndex >= readAddresses.count {
          finishDump()
        } else {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { self.readNextDump() }
        }
      }
      return
    }

    if step == 4, rxBuffer.contains(0x06) {
      rxBuffer.removeAll()
      if writeIndex % 32 == 0 || writeIndex >= writeFrames.count {
        print("WRITE_ACK \(writeIndex)/\(writeFrames.count)")
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.writeNextPair() }
      return
    }

    if step == 5 {
      guard readIndex < writeFrames.count else { return }
      let frame = writeFrames[readIndex]
      if let payload = extractPayload(address: frame.address) {
        if payload != frame.payload {
          print("VERIFY_FAIL \(addrHex(frame.address))")
          print("expected \(hex(Array(frame.payload.prefix(16)))) ...")
          print("actual   \(hex(Array(payload.prefix(16)))) ...")
          finish()
          return
        }
        if readIndex % 32 == 0 || readIndex == writeFrames.count - 1 {
          print("VERIFY \(readIndex + 1)/\(writeFrames.count) \(addrHex(frame.address))")
        }
        readIndex += 1
        rxBuffer.removeAll()
        if readIndex >= writeFrames.count {
          print("VERIFY_OK \(writeFrames.count) blocks")
          send([0x45], label: "END 45")
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.finish() }
        } else {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { self.readNextVerify() }
        }
      }
    }
  }

  private func readNextDump() {
    let address = readAddresses[readIndex]
    step = 3
    rxBuffer.removeAll()
    send([0x52, UInt8((address >> 8) & 0xff), UInt8(address & 0xff), 0x40], label: "READ \(addrHex(address))")
  }

  private func writeNextPair() {
    step = 4
    guard writeIndex < writeFrames.count else {
      switch mode {
      case .write(_, let verify) where verify:
        readIndex = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.readNextVerify() }
      default:
        send([0x45], label: "END 45")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.finish() }
      }
      return
    }
    let first = writeFrames[writeIndex]
    let second = writeFrames[writeIndex + 1]
    print("WRITE \(writeIndex + 1)-\(writeIndex + 2)/\(writeFrames.count) \(addrHex(first.address))/\(addrHex(second.address))")
    rxBuffer.removeAll()
    if streamPairWrite && second.address == first.address + 0x40 {
      send(writeHeader(first.address), label: "WRITE \(addrHex(first.address)) HEADER")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
        self.send(first.payload, label: "WRITE \(addrHex(first.address)) DATA")
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        self.send(second.payload, label: "WRITE \(addrHex(second.address)) DATA")
      }
      writeIndex += 2
      return
    }
    sendMemoryWrite(first, label: "WRITE \(addrHex(first.address))")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      self.sendMemoryWrite(second, label: "WRITE \(addrHex(second.address))")
    }
    writeIndex += 2
  }

  private func readNextVerify() {
    let address = writeFrames[readIndex].address
    step = 5
    rxBuffer.removeAll()
    send([0x52, UInt8((address >> 8) & 0xff), UInt8(address & 0xff), 0x40], label: "VERIFY_READ \(addrHex(address))")
  }

  private func finishDump() {
    guard case .dump(let path) = mode else { return }
    let file = MemoryFile(generatedAt: isoNow(), source: "ble", frames: dumpFrames)
    do {
      let data = try JSONEncoder().encode(file)
      try data.write(to: URL(fileURLWithPath: path))
      print("DUMP_SAVED \(path) \(dumpFrames.count) blocks")
    } catch {
      print("DUMP_SAVE_ERROR \(error)")
    }
    send([0x45], label: "END 45")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.finish() }
  }

  private func loadWritePlan(_ path: String) {
    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      let frames = try JSONDecoder().decode(MemoryFile.self, from: data).frames
      writeFrames = streamPairWrite ? groupBluetoothWriteFrames(frames) : frames
      if writeFrames.count % 2 != 0 {
        print("PLAN_ERROR odd frame count \(writeFrames.count)")
        finish()
      }
      print("PLAN_LOADED \(writeFrames.count) blocks")
    } catch {
      print("PLAN_LOAD_ERROR \(error)")
      finish()
    }
  }

  private func sendMemoryWrite(_ frame: MemoryFrame, label: String) {
    let header = writeHeader(frame.address)
    if splitWrite {
      send(header, label: "\(label) HEADER")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
        self.send(frame.payload, label: "\(label) DATA")
      }
      return
    }
    send(header + frame.payload, label: label)
  }

  private func writeHeader(_ address: Int) -> [UInt8] {
    [UInt8]([0x57, UInt8((address >> 8) & 0xff), UInt8(address & 0xff), 0x40])
  }

  private func extractPayload(address: Int) -> [UInt8]? {
    let high = UInt8((address >> 8) & 0xff)
    let low = UInt8(address & 0xff)
    var index = 0
    while index + 68 <= rxBuffer.count {
      if rxBuffer[index] == 0x52, rxBuffer[index + 1] == high, rxBuffer[index + 2] == low, rxBuffer[index + 3] == 0x40 {
        return Array(rxBuffer[(index + 4)..<(index + 68)])
      }
      index += 1
    }
    return nil
  }

  private func send(_ bytes: [UInt8], label: String) {
    guard let peripheral, let characteristic else {
      print("missing FFE1")
      finish()
      return
    }
    print("TX \(label) \(bytes.count > 20 ? "\(hex(Array(bytes.prefix(20)))) ..." : hex(bytes))")
    peripheral.writeValue(Data(bytes), for: characteristic, type: .withResponse)
  }

  private func finish() {
    timer?.invalidate()
    print("DONE")
    CFRunLoopStop(CFRunLoopGetMain())
  }
}

func props(_ properties: CBCharacteristicProperties) -> String {
  var values: [String] = []
  if properties.contains(.read) { values.append("read") }
  if properties.contains(.write) { values.append("write") }
  if properties.contains(.writeWithoutResponse) { values.append("writeWithoutResponse") }
  if properties.contains(.notify) { values.append("notify") }
  return values.joined(separator: ",")
}

func hex(_ bytes: [UInt8]) -> String {
  bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

func addrHex(_ address: Int) -> String {
  String(format: "%04X", address)
}

func isoNow() -> String {
  ISO8601DateFormatter().string(from: Date())
}

func groupBluetoothWriteFrames(_ frames: [MemoryFrame]) -> [MemoryFrame] {
  let pairStride = 0x40
  let byAddress = Dictionary(uniqueKeysWithValues: frames.map { ($0.address, $0) })
  var used = Set<Int>()
  var grouped: [MemoryFrame] = []

  for first in frames {
    if used.contains(first.address) { continue }

    if let streamSecond = byAddress[first.address + pairStride], !used.contains(streamSecond.address) {
      grouped.append(first)
      grouped.append(streamSecond)
      used.insert(first.address)
      used.insert(streamSecond.address)
      continue
    }

    let fallback = frames.first { candidate in
      if candidate.address == first.address || used.contains(candidate.address) { return false }
      return byAddress[candidate.address - pairStride] == nil && byAddress[candidate.address + pairStride] == nil
    } ?? frames.first { candidate in
      candidate.address != first.address && !used.contains(candidate.address)
    }

    guard let fallback else {
      grouped.append(first)
      used.insert(first.address)
      continue
    }
    grouped.append(first)
    grouped.append(fallback)
    used.insert(first.address)
    used.insert(fallback.address)
  }

  return grouped
}

let readAddresses: [Int] = {
  var values = stride(from: 0, to: 0x4000, by: 64).map { $0 }
  values.append(0x8000)
  values.append(0x9000)
  values.append(contentsOf: stride(from: 0xa000, through: 0xa100, by: 64).map { $0 })
  values.append(contentsOf: [0xa200, 0xa240, 0xb000])
  return values
}()

let args = Array(CommandLine.arguments.dropFirst())
let mode: TransferMode
if let dumpIndex = args.firstIndex(of: "--dump"), dumpIndex + 1 < args.count {
  mode = .dump(args[dumpIndex + 1])
} else if let writeIndex = args.firstIndex(of: "--write"), writeIndex + 1 < args.count {
  mode = .write(args[writeIndex + 1], verify: args.contains("--verify"))
} else {
  print("usage: swift tools/ble-memory-transfer.swift --dump <dump.json> | --write <plan.json> [--verify] [--name walkie]")
  exit(2)
}

let targetName: String = {
  if let nameIndex = args.firstIndex(of: "--name"), nameIndex + 1 < args.count {
    return args[nameIndex + 1]
  }
  return "walkie"
}()

let transfer = BleMemoryTransfer(mode: mode, splitWrite: args.contains("--split"), streamPairWrite: args.contains("--stream-pair"), targetName: targetName)
withExtendedLifetime(transfer) {
  CFRunLoopRun()
}
