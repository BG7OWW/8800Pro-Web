export interface RadioTransport {
  readonly kind: 'serial' | 'bluetooth'
  readonly label: string
  open(): Promise<void>
  close(): Promise<void>
  isConnected(): boolean
  write(data: Uint8Array): Promise<void>
  read(length: number, timeoutMs?: number): Promise<Uint8Array>
  drain?(): void
  reopen?(): Promise<void>
}

export class TransportTimeoutError extends Error {
  constructor(message = '读取设备超时') {
    super(message)
    this.name = 'TransportTimeoutError'
  }
}

export class ByteQueue {
  private queue: number[] = []
  private waiters: Array<() => void> = []

  push(data: Uint8Array) {
    this.queue.push(...data)
    this.waiters.splice(0).forEach((resolve) => resolve())
  }

  clear() {
    this.queue = []
  }

  async read(length: number, timeoutMs = 4000) {
    const startedAt = Date.now()
    while (this.queue.length < length) {
      const remaining = timeoutMs - (Date.now() - startedAt)
      if (remaining <= 0) throw new TransportTimeoutError()
      await new Promise<void>((resolve, reject) => {
        const timer = window.setTimeout(() => {
          this.waiters = this.waiters.filter((waiter) => waiter !== done)
          reject(new TransportTimeoutError())
        }, remaining)
        const done = () => {
          window.clearTimeout(timer)
          resolve()
        }
        this.waiters.push(done)
      })
    }
    return new Uint8Array(this.queue.splice(0, length))
  }
}
