import { ByteQueue, type RadioTransport } from './transport'

export class WebSerialTransport implements RadioTransport {
  readonly kind = 'serial' as const
  readonly label = 'USB 写频线'
  private port?: SerialPort
  private reader?: ReadableStreamDefaultReader<Uint8Array>
  private writer?: WritableStreamDefaultWriter<Uint8Array>
  private queue = new ByteQueue()
  private abort = false
  private connected = false
  private readonly options: SerialOptions = {
    baudRate: 115200,
    dataBits: 8,
    stopBits: 1,
    parity: 'none',
    bufferSize: 102400,
  }

  static isSupported() {
    return 'serial' in navigator
  }

  async open() {
    if (!WebSerialTransport.isSupported()) throw new Error('当前浏览器不支持 Web Serial，请使用桌面 Chrome 或 Edge。')
    this.port = await navigator.serial.requestPort()
    await this.openCurrentPort()
  }

  async close() {
    this.abort = true
    this.connected = false
    try {
      await this.reader?.cancel()
      this.reader?.releaseLock()
    } catch {
      // ignore close races
    }
    try {
      this.writer?.releaseLock()
      await this.port?.close()
    } catch {
      // ignore close races
    }
  }

  async reopen() {
    if (!this.port) throw new Error('串口未连接')
    this.abort = true
    this.connected = false
    try {
      await this.reader?.cancel()
      this.reader?.releaseLock()
    } catch {
      // ignore close races
    }
    try {
      this.writer?.releaseLock()
      await this.port.close()
    } catch {
      // ignore close races
    }
    await sleep(160)
    await this.openCurrentPort()
    this.queue.clear()
  }

  isConnected() {
    return this.connected && Boolean(this.port?.readable) && Boolean(this.port?.writable)
  }

  async write(data: Uint8Array) {
    if (!this.writer) throw new Error('串口未连接')
    await this.writer.write(data)
  }

  read(length: number, timeoutMs?: number) {
    return this.queue.read(length, timeoutMs)
  }

  drain() {
    this.queue.clear()
  }

  private async readLoop() {
    while (!this.abort && this.reader) {
      try {
        const { value, done } = await this.reader.read()
        if (done) break
        if (value) this.queue.push(value)
      } catch {
        this.connected = false
        if (!this.abort) break
      }
    }
  }

  private async openCurrentPort() {
    if (!this.port) throw new Error('串口未连接')
    await this.port.open(this.options)
    await this.port.setSignals?.({ dataTerminalReady: true, requestToSend: true })
    this.writer = this.port.writable?.getWriter()
    this.reader = this.port.readable?.getReader()
    this.abort = false
    this.connected = true
    void this.readLoop()
    await sleep(120)
  }
}

function sleep(ms: number) {
  return new Promise((resolve) => window.setTimeout(resolve, ms))
}
