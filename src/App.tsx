import {
  Activity,
  Archive,
  Bluetooth,
  Cable,
  CircleHelp,
  Copy,
  Database,
  FileDown,
  FileSpreadsheet,
  FileUp,
  Image,
  ListChecks,
  Menu,
  PanelLeftClose,
  PanelLeftOpen,
  Radio,
  RotateCcw,
  Save,
  Satellite,
  Scissors,
  SlidersHorizontal,
  Sparkles,
  SquareArrowOutUpRight,
  Trash2,
  Upload,
  Waves,
  X,
} from 'lucide-react'
import { useCallback, useEffect, useMemo, useRef, useState, type ChangeEvent, type ReactNode } from 'react'
import './App.css'
import hamLogo from './assets/ham-logo.png'
import { CHANNEL_CHOICES, DTMF_CHOICES, FUNCTION_CHOICES, TONE_CHOICES, VFO_CHOICES } from './core/constants/choices'
import { SHX8800PRO } from './core/constants/memory-map'
import { normalizeRadioFrequency } from './core/codec/frequency'
import { countVisibleChannels, createDefaultAppData, createEmptyChannel, cloneAppData, type AppData, type Channel, type FunctionSettings } from './core/models/radio'
import { Shx8800ProSession, type BluetoothWriteMode, type SessionProgress } from './core/protocol/shx8800pro-session'
import { WebBluetoothTransport } from './transport/web-bluetooth-transport'
import { WebSerialTransport } from './transport/web-serial-transport'
import type { RadioTransport } from './transport/transport'
import { deleteBackup, listBackups, saveBackup, type BackupRecord } from './lib/backup'
import { downloadJson, exportCsv, exportExcel, importExcel, loadJsonFile } from './lib/import-export'
import { loadBootImage } from './lib/boot-image'
import { buildChannelFromRepeater, createFallbackRepeaterPackage, describeRepeater, loadRepeaterLibrary, type RepeaterEntry, type RepeaterLibraryPackage } from './lib/repeaters'
import { createSatelliteChannels, fetchSatelliteModes, type SatelliteMode } from './lib/satellite'

type ViewId = 'dashboard' | 'channels' | 'vfo' | 'settings' | 'dtmf' | 'fm' | 'boot' | 'satellite' | 'files' | 'guide' | 'about' | 'debug'
type UiMode = 'simple' | 'pro'

const navItems: Array<{ id: ViewId; label: string; icon: ReactNode }> = [
  { id: 'dashboard', label: '总览', icon: <Activity /> },
  { id: 'channels', label: '信道', icon: <ListChecks /> },
  { id: 'vfo', label: 'VFO', icon: <Waves /> },
  { id: 'settings', label: '功能', icon: <SlidersHorizontal /> },
  { id: 'dtmf', label: 'DTMF', icon: <Radio /> },
  { id: 'fm', label: 'FM', icon: <Radio /> },
  { id: 'boot', label: '开机图', icon: <Image /> },
  { id: 'satellite', label: '打星', icon: <Satellite /> },
  { id: 'files', label: '文件', icon: <Archive /> },
  { id: 'guide', label: '教程', icon: <CircleHelp /> },
  { id: 'debug', label: '日志', icon: <Database /> },
]

const viewTitles: Record<ViewId, string> = {
  dashboard: '总览',
  channels: '信道',
  vfo: 'VFO',
  settings: '功能',
  dtmf: 'DTMF',
  fm: 'FM',
  boot: '开机图',
  satellite: '打星',
  files: '文件',
  guide: '教程',
  about: '关于',
  debug: '日志',
}

function App() {
  const [activeView, setActiveView] = useState<ViewId>('dashboard')
  const [uiMode, setUiMode] = useState<UiMode>('simple')
  const [data, setData] = useState<AppData>(() => createDefaultAppData())
  const [transport, setTransport] = useState<RadioTransport | null>(null)
  const [progress, setProgress] = useState<SessionProgress | null>(null)
  const [logs, setLogs] = useState<string[]>([])
  const [busy, setBusy] = useState(false)
  const [reconnectAttempt, setReconnectAttempt] = useState(0)
  const [mobileNavOpen, setMobileNavOpen] = useState(false)
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [backups, setBackups] = useState<BackupRecord[]>([])
  const [notice, setNotice] = useState<{ tone: 'idle' | 'ok' | 'warn'; text: string } | null>(null)
  const [channelEditorResetKey, setChannelEditorResetKey] = useState(0)
  const [baselineData, setBaselineData] = useState<AppData>(() => cloneAppData(createDefaultAppData()))
  const [diffReviewMode, setDiffReviewMode] = useState<'write' | 'view' | null>(null)
  const [pendingWriteMode, setPendingWriteMode] = useState<BluetoothWriteMode>('official')
  const abortRef = useRef<AbortController | null>(null)
  const busyRef = useRef(false)
  const reconnectingRef = useRef(false)
  const manualDisconnectRef = useRef(false)
  const showBeian = import.meta.env.MODE === 'server'

  useEffect(() => {
    void refreshBackups()
  }, [])

  const stats = useMemo(
    () => ({
      visibleChannels: countVisibleChannels(data),
      lastUpdated: new Date(data.updatedAt).toLocaleString(),
      serialSupported: WebSerialTransport.isSupported(),
      bluetoothSupported: WebBluetoothTransport.isSupported(),
      activeBankSummary:
        data.functions.currentBankA === data.functions.currentBankB
          ? data.bankNames[data.functions.currentBankA] ?? `区域 ${data.functions.currentBankA + 1}`
          : `A ${data.bankNames[data.functions.currentBankA] ?? `区域 ${data.functions.currentBankA + 1}`} / B ${data.bankNames[data.functions.currentBankB] ?? `区域 ${data.functions.currentBankB + 1}`}`,
    }),
    [data],
  )
  const diffSummary = useMemo(() => summarizeAppDataDiff(baselineData, data), [baselineData, data])
  const visibleNavItems = uiMode === 'simple' ? navItems.filter((item) => ['dashboard', 'channels', 'settings', 'files', 'guide', 'debug'].includes(item.id)) : navItems

  function switchUiMode(mode: UiMode) {
    setUiMode(mode)
    if (mode === 'simple' && !['dashboard', 'channels', 'settings', 'files', 'guide', 'debug'].includes(activeView)) {
      setActiveView('dashboard')
    }
  }

  function switchView(view: ViewId) {
    setActiveView(view)
    setMobileNavOpen(false)
  }

  async function refreshBackups() {
    setBackups(await listBackups())
  }

  const addLog = useCallback((line: string) => {
    setLogs((current) => [`${new Date().toLocaleTimeString()}  ${line}`, ...current].slice(0, 300))
  }, [])

  useEffect(() => {
    busyRef.current = busy
  }, [busy])

  useEffect(() => {
    if (!transport) return
    let cancelled = false

    const validateTransportHealthy = async () => {
      if (!transport.isConnected()) return false
      if (transport.kind !== 'serial') return true
      try {
        await new Shx8800ProSession(transport).validateConnection()
        return true
      } catch (error) {
        const message = error instanceof Error ? error.message : '未知错误'
        addLog(`USB 握手校验失败：${message}`)
        return false
      }
    }

    const syncConnection = async () => {
      if (cancelled || manualDisconnectRef.current || reconnectingRef.current) return
      if (busyRef.current) return
      if (await validateTransportHealthy()) {
        setReconnectAttempt(0)
        return
      }
      if (!transport.reopen) {
        markDisconnected('设备断开连接，当前状态已切换为未连接。')
        return
      }

      reconnectingRef.current = true
      for (let attempt = 1; attempt <= 3 && !cancelled; attempt += 1) {
        setReconnectAttempt(attempt)
        setNotice({ tone: 'warn', text: `设备临时断开，正在自动重连（${attempt}/3）。` })
        addLog(`设备断开，正在自动重连（${attempt}/3）`)
        try {
          await wait(1500)
          await transport.reopen()
          if (await validateTransportHealthy()) {
            setReconnectAttempt(0)
            setNotice({ tone: 'ok', text: '设备已自动重连，可以继续读频或写频。' })
            addLog('设备已自动重连')
            reconnectingRef.current = false
            return
          }
        } catch (error) {
          const message = error instanceof Error ? error.message : '未知错误'
          addLog(`自动重连失败（${attempt}/3）：${message}`)
        }
      }
      reconnectingRef.current = false
      if (!cancelled) markDisconnected('自动重连 3 次失败，已切换为未连接。')
    }

    const markDisconnected = (message: string) => {
      abortRef.current?.abort()
      setBusy(false)
      setProgress(null)
      setTransport(null)
      setReconnectAttempt(0)
      setNotice({ tone: 'warn', text: message })
      addLog('设备断开连接，已切换为未连接')
    }

    void syncConnection()
    const timer = window.setInterval(() => void syncConnection(), 1500)
    return () => {
      cancelled = true
      window.clearInterval(timer)
    }
  }, [transport, addLog])

  async function connectSerial() {
    await withBusy(async () => {
      manualDisconnectRef.current = true
      try {
        await transport?.close()
      } finally {
        manualDisconnectRef.current = false
      }
      const next = new WebSerialTransport()
      try {
        await next.open()
        const session = new Shx8800ProSession(next, {
          onLog: addLog,
          onProgress: setProgress,
        })
        await session.validateConnection()
      } catch (error) {
        await next.close().catch(() => undefined)
        throw error
      }
      setTransport(next)
      setReconnectAttempt(0)
      setProgress(null)
      setNotice({ tone: 'ok', text: 'USB 写频线和对讲机握手成功，可以先点“读频”。' })
      addLog('USB 写频线已连接，设备握手校验通过')
    })
  }

  async function connectBluetooth() {
    await withBusy(async () => {
      manualDisconnectRef.current = true
      try {
        await transport?.close()
      } finally {
        manualDisconnectRef.current = false
      }
      const next = new WebBluetoothTransport()
      await next.open()
      setTransport(next)
      setReconnectAttempt(0)
      setNotice({ tone: 'ok', text: '蓝牙已连接。第一次正式整机读写仍建议优先用 USB。' })
      addLog('蓝牙 FFE0/FFE1 已连接，8800Pro 写入仍需回读校验')
    })
  }

  async function disconnect() {
    manualDisconnectRef.current = true
    await transport?.close()
    setTransport(null)
    setReconnectAttempt(0)
    setNotice({ tone: 'idle', text: '设备已断开。重新连接后可以继续读频或写频。' })
    addLog('设备连接已断开')
    await wait(120)
    manualDisconnectRef.current = false
  }

  async function readRadio() {
    if (!transport) return
    await withBusy(async () => {
      await saveBackup(data, '读频前自动备份')
      await refreshBackups()
      const abort = new AbortController()
      abortRef.current = abort
      const session = new Shx8800ProSession(transport, {
        signal: abort.signal,
        onLog: addLog,
        onProgress: setProgress,
      })
      const next = await session.readRadio()
      setData(next)
      setBaselineData(cloneAppData(next))
      setChannelEditorResetKey((key) => key + 1)
      setActiveView('channels')
      setNotice({ tone: 'ok', text: `读频完成，已切换到 ${next.bankNames[getPreferredBankIndex(next)]}。` })
      await saveBackup(next, '读频完成')
      await refreshBackups()
      addLog('读频完成')
    })
  }

  async function writeRadio(mode: BluetoothWriteMode = 'official') {
    setPendingWriteMode(mode)
    if (diffSummary.totalChanges > 0) {
      setDiffReviewMode('write')
      return
    }
    await performWriteRadio(mode)
  }

  async function performWriteRadio(mode: BluetoothWriteMode = 'official') {
    if (!transport) return
    await withBusy(async () => {
      await saveBackup(data, '写频前自动备份')
      await refreshBackups()
      const abort = new AbortController()
      abortRef.current = abort
      const session = new Shx8800ProSession(transport, {
        signal: abort.signal,
        onLog: addLog,
        onProgress: setProgress,
        bluetoothWriteMode: transport.kind === 'bluetooth' ? mode : 'official',
      })
      await session.writeRadio(data)
      setNotice({ tone: 'ok', text: `${transport.kind === 'bluetooth' ? '蓝牙' : 'USB'} 写频完成。建议再点一次“读频”确认机器内容。` })
      addLog(`${transport.kind === 'bluetooth' ? '蓝牙' : 'USB'} 写频完成`)
      setBaselineData(cloneAppData(data))
    })
  }

  async function writeBootImage() {
    if (!transport || !data.bootImage?.rgb565) return
    if (transport.kind === 'bluetooth') {
      const message = '蓝牙写开机图正在开发中，请使用写频线。'
      setNotice({ tone: 'warn', text: message })
      addLog(message)
      return
    }
    await withBusy(async () => {
      const abort = new AbortController()
      abortRef.current = abort
      const session = new Shx8800ProSession(transport, {
        signal: abort.signal,
        onLog: addLog,
        onProgress: setProgress,
      })
      await session.writeBootImage(new Uint8Array(data.bootImage?.rgb565 ?? []))
      setNotice({ tone: 'ok', text: '开机图写入完成。重启对讲机后可以直接看屏幕确认。' })
      addLog(transport.kind === 'bluetooth' ? '蓝牙开机图写入完成，请重启设备人工确认画面' : 'USB 开机图写入完成')
    })
  }

  async function withBusy(task: () => Promise<void>) {
    try {
      setBusy(true)
      setNotice(null)
      await task()
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误'
      setNotice({ tone: 'warn', text: `操作失败：${message}` })
      setActiveView('debug')
      addLog(`错误：${message}`)
    } finally {
      setBusy(false)
      abortRef.current = null
    }
  }

  function cancelOperation() {
    abortRef.current?.abort()
    addLog('已请求取消当前操作')
  }

  if (!transport) {
    return (
      <ConnectionGate
        busy={busy}
        notice={notice}
        stats={stats}
        reconnectAttempt={reconnectAttempt}
        showBeian={showBeian}
        onConnectSerial={() => void connectSerial()}
        onConnectBluetooth={() => void connectBluetooth()}
      />
    )
  }

  return (
    <div className={`app-shell ${sidebarCollapsed ? 'sidebar-collapsed' : ''}`}>
      <button type="button" className="mobile-nav-toggle" onClick={() => setMobileNavOpen(true)} aria-label="打开导航">
        <Menu size={20} />
      </button>
      {mobileNavOpen ? <button type="button" className="mobile-nav-scrim" aria-label="关闭导航" onClick={() => setMobileNavOpen(false)} /> : null}
      <aside className={`sidebar ${mobileNavOpen ? 'open' : ''}`}>
        <div className="brand">
          <button
            type="button"
            className="sidebar-rail-toggle"
            onClick={() => setSidebarCollapsed(false)}
            title="展开菜单栏"
            aria-label="展开菜单栏"
          >
            <PanelLeftOpen size={18} />
          </button>
          <div className="brand-mark">
            <img src={hamLogo} alt="8800Pro Web logo" />
          </div>
          <div className="brand-copy">
            <strong>8800Pro Web</strong>
          </div>
          <button
            type="button"
            className="sidebar-collapse-button"
            onClick={() => setSidebarCollapsed(true)}
            title="收起菜单栏"
            aria-label="收起菜单栏"
          >
            <PanelLeftClose size={18} />
          </button>
          <button type="button" className="mobile-nav-close" onClick={() => setMobileNavOpen(false)} aria-label="关闭导航">
            <X size={18} />
          </button>
        </div>
        <div className="collapsed-mode-switch" role="tablist" aria-label="界面模式">
          <button type="button" className={uiMode === 'simple' ? 'active' : ''} onClick={() => switchUiMode('simple')} title="基础模式" aria-label="基础模式">
            <ListChecks size={17} />
          </button>
          <button type="button" className={uiMode === 'pro' ? 'active' : ''} onClick={() => switchUiMode('pro')} title="高级模式" aria-label="高级模式">
            <SlidersHorizontal size={17} />
          </button>
        </div>
        <div className="mode-switch" role="tablist" aria-label="界面模式">
          <button type="button" className={uiMode === 'simple' ? 'active' : ''} onClick={() => switchUiMode('simple')}>
            基础
          </button>
          <button type="button" className={uiMode === 'pro' ? 'active' : ''} onClick={() => switchUiMode('pro')}>
            高级
          </button>
        </div>
        <nav>
          {visibleNavItems.map((item) => (
            <button
              key={item.id}
              type="button"
              className={activeView === item.id ? 'active' : ''}
              title={item.label}
              onClick={() => switchView(item.id)}
            >
              {item.icon}
              <span>{item.label}</span>
            </button>
          ))}
        </nav>
        {uiMode === 'simple' && (
          <div className="sidebar-note">
            <strong>基础模式</strong>
            <span>对讲机基础功能，更多功能请点击“高级“按钮进入高级模式使用</span>
          </div>
        )}
        <div className="sidebar-footer">
          <a className="about-card" href="/about/">
            <strong>BG7OWW</strong>
            <SquareArrowOutUpRight size={16} />
          </a>
          {showBeian ? (
            <div className="beian-links">
              <a href="https://beian.miit.gov.cn/" rel="noreferrer" target="_blank">
                <span>粤ICP备2023143201号</span>
              </a>
              <a href="https://beian.mps.gov.cn/#/query/webSearch?code=44011302005027" rel="noreferrer" target="_blank">
                <img src="https://img.743.world/i/2026/03/25/124l7ch.webp" alt="公安备案图标" />
                <span>粤公网安备44011302005027号</span>
              </a>
            </div>
          ) : null}
        </div>
      </aside>

      <main className="workspace">
        <header className="topbar">
          <div className="topbar-title">
            <h1>{viewTitles[activeView]}</h1>
            <p>网页多功能控制台</p>
          </div>
          <div className="connection-strip">
            <button type="button" className="primary-button" onClick={readRadio} disabled={busy || !transport}>
              <FileDown size={18} />
              读频
            </button>
            {transport?.kind === 'bluetooth' ? (
              <>
                <button type="button" className="primary-button warn" onClick={() => void writeRadio('official')} disabled={busy || !transport}>
                  <Upload size={18} />
                  常规写频
                </button>
                <button type="button" className="primary-button fast" onClick={() => void writeRadio('legacy')} disabled={busy || !transport}>
                  <Waves size={18} />
                  快速写频
                </button>
              </>
            ) : (
              <button type="button" className="primary-button warn" onClick={() => void writeRadio('official')} disabled={busy || !transport}>
                <Upload size={18} />
                写频
              </button>
            )}
            {busy ? (
              <button type="button" className="ghost-button" onClick={cancelOperation}>
                取消
              </button>
            ) : (
              <button type="button" className="ghost-button" onClick={disconnect} disabled={!transport}>
                断开连接
              </button>
            )}
          </div>
        </header>

        <StatusRail transport={transport} progress={progress} busy={busy} stats={stats} backupCount={backups.length} />
        {notice ? <OperationNotice tone={notice.tone} text={notice.text} /> : null}

        {activeView === 'dashboard' && (
          <Dashboard
            data={data}
            stats={stats}
            backups={backups}
            setActiveView={setActiveView}
            transport={transport}
            onSwitchMode={switchUiMode}
            uiMode={uiMode}
          />
        )}
        {activeView === 'channels' && <ChannelEditor key={channelEditorResetKey} data={data} setData={setData} addLog={addLog} />}
        {activeView === 'vfo' && <VfoPanel data={data} setData={setData} />}
        {activeView === 'settings' && <SettingsPanel data={data} setData={setData} />}
        {activeView === 'dtmf' && <DtmfPanel data={data} setData={setData} />}
        {activeView === 'fm' && <FmPanel key={`${data.fm.currentFreq}:${data.fm.channels.join(',')}`} data={data} setData={setData} />}
        {activeView === 'boot' && (
          <BootImagePanel
            data={data}
            setData={setData}
            addLog={addLog}
            canWrite={Boolean(transport && data.bootImage?.rgb565)}
            busy={busy}
            transportKind={transport?.kind}
            onWrite={() => void writeBootImage()}
          />
        )}
        {activeView === 'satellite' && <SatellitePanel data={data} setData={setData} addLog={addLog} />}
        {activeView === 'files' && (
          <FilesPanel
            data={data}
            setData={setData}
            setBaselineData={setBaselineData}
            backups={backups}
            refreshBackups={refreshBackups}
            addLog={addLog}
            diffSummary={diffSummary}
            onOpenDiff={() => setDiffReviewMode('view')}
          />
        )}
        {activeView === 'guide' && <GuidePanel setActiveView={setActiveView} />}
        {activeView === 'about' && <AboutPanel />}
        {activeView === 'debug' && <DebugPanel logs={logs} clear={() => setLogs([])} />}
      </main>
      <DiffReviewDialog
        open={diffReviewMode !== null}
        mode={diffReviewMode}
        summary={diffSummary}
        confirmLabel={pendingWriteMode === 'legacy' ? '确认快速写频' : '确认写频'}
        confirmTone={pendingWriteMode === 'legacy' ? 'fast' : 'warn'}
        onClose={() => setDiffReviewMode(null)}
        onConfirm={() => {
          setDiffReviewMode(null)
          void performWriteRadio(pendingWriteMode)
        }}
      />
    </div>
  )
}

function ConnectionGate({
  busy,
  notice,
  stats,
  reconnectAttempt,
  showBeian,
  onConnectSerial,
  onConnectBluetooth,
}: {
  busy: boolean
  notice: { tone: 'idle' | 'ok' | 'warn'; text: string } | null
  stats: { serialSupported: boolean; bluetoothSupported: boolean }
  reconnectAttempt: number
  showBeian: boolean
  onConnectSerial: () => void
  onConnectBluetooth: () => void
}) {
  return (
    <main className="connection-gate">
      <section className="connection-stage" aria-label="连接设备">
        <div className="connection-orbit" aria-hidden="true">
          <i />
          <i />
          <i />
        </div>
        <div className="connection-brand">
          <div className="brand-mark">
            <img src={hamLogo} alt="8800Pro Web logo" />
          </div>
          <span>8800Pro Web</span>
        </div>
        <div className="connection-copy">
          <h1>先连接设备</h1>
          <p>选择蓝牙或 USB 写频线，连接成功后进入读频、编辑和写频控制台。</p>
        </div>
        <div className="connection-actions">
          <button type="button" className="connect-choice bluetooth" onClick={onConnectBluetooth} disabled={busy || !stats.bluetoothSupported}>
            <Bluetooth size={28} />
            <strong>{busy ? '连接中' : '蓝牙连接'}</strong>
            <span>{stats.bluetoothSupported ? '适合无线读写频' : '当前浏览器不支持 Web Bluetooth'}</span>
          </button>
          <button type="button" className="connect-choice serial" onClick={onConnectSerial} disabled={busy || !stats.serialSupported}>
            <Cable size={28} />
            <strong>USB 写频线</strong>
            <span>{stats.serialSupported ? '适合首次备份和稳定写入' : '当前浏览器不支持 Web Serial'}</span>
          </button>
        </div>
        <p className="connection-compat">移动端直连请使用 Android Chrome / Edge。iOS / iPadOS 的 Safari、Chrome、Edge 等普通浏览器目前不提供本项目需要的 Web Bluetooth GATT 或 Web Serial API，可以浏览、编辑和导入导出配置；专用 BLE 浏览器或原生桥接属于实验路线。</p>
        {notice ? <OperationNotice tone={notice.tone} text={notice.text} /> : null}
        {reconnectAttempt > 0 ? <p className="connection-footnote">正在自动重连：{reconnectAttempt}/3</p> : null}
        <footer className="connection-footer">
          <strong>Made by BG7OWW</strong>
          {showBeian ? (
            <div className="beian-links connection-beian">
              <a href="https://beian.miit.gov.cn/" rel="noreferrer" target="_blank">
                <span>粤ICP备2023143201号</span>
              </a>
              <a href="https://beian.mps.gov.cn/#/query/webSearch?code=44011302005027" rel="noreferrer" target="_blank">
                <img src="https://img.743.world/i/2026/03/25/124l7ch.webp" alt="公安备案图标" />
                <span>粤公网安备44011302005027号</span>
              </a>
            </div>
          ) : null}
        </footer>
      </section>
    </main>
  )
}

function OperationNotice({ tone, text }: { tone: 'idle' | 'ok' | 'warn'; text: string }) {
  return (
    <section className={`operation-notice ${tone}`}>
      <strong>{tone === 'warn' ? '需要处理' : tone === 'ok' ? '操作状态' : '提示'}</strong>
      <span>{text}</span>
    </section>
  )
}

function DiffReviewDialog({
  open,
  mode,
  summary,
  confirmLabel,
  confirmTone,
  onClose,
  onConfirm,
}: {
  open: boolean
  mode: 'write' | 'view' | null
  summary: AppDataDiffSummary
  confirmLabel: string
  confirmTone: 'warn' | 'fast'
  onClose: () => void
  onConfirm: () => void
}) {
  if (!open) return null
  const isWrite = mode === 'write'
  return (
    <div className="modal-layer" role="dialog" aria-modal="true" aria-label="差异对比">
      <button type="button" className="modal-scrim" aria-label="关闭差异对比" onClick={onClose} />
      <section className="diff-dialog">
        <div className="panel-heading compact-actions">
          <div>
            <h3>{isWrite ? '写频前审查' : '差异对比'}</h3>
            <p>当前配置相对最近读频、导入或恢复的基准镜像共有 {summary.totalChanges} 项变化。</p>
          </div>
          <button type="button" className="ghost-button" onClick={onClose}>关闭</button>
        </div>
        <DiffSummaryBody summary={summary} />
        <div className="diff-footer">
          {isWrite ? (
            <button type="button" className={`primary-button ${confirmTone}`} onClick={onConfirm}>
              {confirmTone === 'fast' ? <Waves size={18} /> : <Upload size={18} />}
              {confirmLabel}
            </button>
          ) : null}
        </div>
      </section>
    </div>
  )
}

function DiffSummaryStrip({ summary }: { summary: AppDataDiffSummary }) {
  const topGroups = summary.groups.filter((group) => group.count > 0).slice(0, 3)
  return (
    <div className={`diff-strip ${summary.totalChanges > 0 ? 'changed' : ''}`}>
      <strong>{summary.totalChanges > 0 ? `有 ${summary.totalChanges} 项待写入差异` : '当前配置与基准一致'}</strong>
      <span>{topGroups.length > 0 ? topGroups.map((group) => `${group.label} ${group.count}`).join(' · ') : '读频、导入或恢复后会建立新的基准镜像。'}</span>
    </div>
  )
}

function DiffSummaryBody({ summary }: { summary: AppDataDiffSummary }) {
  if (summary.totalChanges === 0) return <div className="channel-empty">暂无差异。</div>
  return (
    <div className="diff-list">
      {summary.groups.filter((group) => group.count > 0).map((group) => (
        <article key={group.label} className="diff-group">
          <div className="diff-group-title">
            <strong>{group.label}</strong>
            <span>{group.count} 项</span>
          </div>
          {group.items.slice(0, 24).map((item) => (
            <div key={item.path} className="diff-row">
              <span>{item.label}</span>
              <del>{formatDiffValue(item.before)}</del>
              <ins>{formatDiffValue(item.after)}</ins>
            </div>
          ))}
          {group.items.length > 24 ? <small>还有 {group.items.length - 24} 项未展开</small> : null}
        </article>
      ))}
    </div>
  )
}

function StatusRail({
  transport,
  progress,
  busy,
  stats,
  backupCount,
}: {
  transport: RadioTransport | null
  progress: SessionProgress | null
  busy: boolean
  stats: {
    visibleChannels: number
    lastUpdated: string
    serialSupported: boolean
    bluetoothSupported: boolean
    activeBankSummary: string
  }
  backupCount: number
}) {
  const availableLinks = [stats.serialSupported ? 'USB' : '', stats.bluetoothSupported ? '蓝牙' : ''].filter(Boolean).join(' / ') || '当前浏览器不支持'
  const deviceLabel = transport ? (transport.isConnected() ? transport.label : '设备断开') : '未连接'
  return (
    <section className="status-rail">
      <Metric label="设备" value={deviceLabel} tone={transport ? (transport.isConnected() ? 'ok' : 'warn') : 'idle'} />
      <Metric label="已启用信道" value={`${stats.visibleChannels}/512`} />
      <Metric label="本地备份" value={`${backupCount} 份`} />
      <Metric label="可连接方式" value={availableLinks} />
      <div className="progress-card">
        <span>{busy ? progress?.label ?? '处理中' : `最近更新 ${stats.lastUpdated}`}</span>
        <div className="progress-track">
          <div style={{ width: `${busy ? progress?.percent ?? 4 : 0}%` }} />
        </div>
      </div>
    </section>
  )
}

function Metric({ label, value, tone = 'idle' }: { label: string; value: string; tone?: 'ok' | 'idle' | 'warn' }) {
  return (
    <div className={`metric ${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  )
}

function Dashboard({
  data,
  stats,
  backups,
  setActiveView,
  transport,
  onSwitchMode,
  uiMode,
}: {
  data: AppData
  stats: { visibleChannels: number; lastUpdated: string; activeBankSummary: string }
  backups: BackupRecord[]
  setActiveView: (view: ViewId) => void
  transport: RadioTransport | null
  onSwitchMode: (mode: UiMode) => void
  uiMode: UiMode
}) {
  const occupiedBanks = data.channels.map((bank) => bank.filter((channel) => channel.visible).length)
  const quickStartSteps = [
    ['1. 连接设备', '第一次建议先读频并自动备份。USB 和蓝牙都可读写，蓝牙会按官方 0x80 原生块写入。', '直接点右上角 USB 或 蓝牙。'],
    ['2. 先点读频', '把手台里原本的数据读出来，系统会自动留原机备份。', '读频完成后再修改。'],
    ['3. 去信道页改内容', '新手最常用的是信道名称、接收频率、发射频率、亚音。', '不会的字段先保持默认。'],
    ['4. 先试一个信道', '先只改 1 个信道测试，确认设备工作正常。', '没问题后再批量修改。'],
    ['5. 写回并验证', '点“写频”把当前内容写回手台。写完后再读频确认一次。', '不满意就去文件页恢复备份。'],
  ] as const
  return (
    <div className="dashboard-grid">
      <section className="hero-panel">
        <div>
          <h2>第一次上手也能顺着做完读频、编辑和写回</h2>
          <p>先连接设备，再点读频保存一份原始备份。改完以后再写回，蓝牙会自动做回读校验，USB 更适合第一次正式操作。</p>
          <div className="hero-actions">
            <button type="button" className="primary-button" onClick={() => setActiveView('channels')}>
              <ListChecks size={18} />
              开始编辑
            </button>
            <button type="button" className="ghost-button" onClick={() => setActiveView('files')}>
              <FileSpreadsheet size={18} />
              备份与导入
            </button>
          </div>
        </div>
        <div className="radio-visual" aria-hidden="true">
          <div className="antenna" />
          <div className="screen">
            <span>A {data.vfos.vfoAFreq}</span>
            <span>B {data.vfos.vfoBFreq}</span>
          </div>
          <div className="keypad">
            {Array.from({ length: 12 }, (_, index) => (
              <i key={index} />
            ))}
          </div>
        </div>
      </section>
      <section className="panel stretch-panel">
        <h3>区域占用</h3>
        <p className="section-note">每个区域可以理解成一组信道。数字越大，表示这个区域里已经配好的信道越多。</p>
        <div className="bank-bars">
          {occupiedBanks.map((count, index) => (
            <button key={index} type="button" onClick={() => setActiveView('channels')}>
              <span>{data.bankNames[index]}</span>
              <strong>{count}</strong>
              <i style={{ width: `${(count / 64) * 100}%` }} />
            </button>
          ))}
        </div>
      </section>
      <section className="panel stretch-panel">
        <h3>新手一步一步来</h3>
        <div className="onboarding-list">
          {quickStartSteps.map(([title, detail, action]) => (
            <div key={title} className="onboarding-item">
              <strong>{title}</strong>
              <span>{detail}</span>
              <small>{action}</small>
            </div>
          ))}
        </div>
      </section>
      <section className="panel stretch-panel">
        <h3>当前配置概览</h3>
        <div className="summary-list">
          <span>有效信道 <strong>{stats.visibleChannels}</strong></span>
          <span>DTMF 组 <strong>{data.dtmf.groups.filter(Boolean).length}</strong></span>
          <span>FM 频道 <strong>{data.fm.channels.filter(Boolean).length}</strong></span>
          <span>备份数量 <strong>{backups.length}</strong></span>
        </div>
      </section>
      <section className="panel next-step-panel stretch-panel">
        <h3>推荐操作</h3>
        <p className="section-note">
          {transport?.kind === 'bluetooth'
            ? '现在适合先读频确认，再去信道页改动并写回。'
            : transport?.kind === 'serial'
              ? 'USB 已连接，建议先读频、再批量编辑，最后写回。'
              : '还没连接设备的话，先看教程，再从读频流程开始。'}
        </p>
        <div className="dashboard-link-grid">
          <button type="button" onClick={() => setActiveView('guide')}>
            <strong>新手教程</strong>
            <span>先把区域、信道、读频这些基础概念看明白。</span>
          </button>
          <button type="button" onClick={() => setActiveView('channels')}>
            <strong>信道编辑</strong>
            <span>最常用的写频入口，改名称、频率、亚音都在这里。</span>
          </button>
          <button type="button" onClick={() => setActiveView('settings')}>
            <strong>功能设置</strong>
            <span>静噪、背光、锁键、双守这些整机选项从这里调。</span>
          </button>
          <button type="button" onClick={() => setActiveView('files')}>
            <strong>备份恢复</strong>
            <span>导出配置、恢复备份、导入 Excel 都在文件页。</span>
          </button>
        </div>
        <div className="summary-list compact-list dashboard-footer-list">
          <span>当前链路 <strong>{transport ? (transport.isConnected() ? (transport.kind === 'bluetooth' ? '蓝牙' : 'USB') : '设备断开') : '未连接'}</strong></span>
          <span>机器默认打开 <strong>{stats.activeBankSummary}</strong></span>
        </div>
      </section>
      <section className="panel mode-panel stretch-panel">
        <h3>界面模式</h3>
        <div className="summary-list">
          <span>当前界面 <strong>{uiMode === 'simple' ? '基础模式' : '高级模式'}</strong></span>
          <span>高级页 <strong>VFO / DTMF / FM / 开机图 / 打星</strong></span>
        </div>
        <div className="action-grid dashboard-footer-actions">
          <button type="button" className="ghost-button" onClick={() => onSwitchMode(uiMode === 'simple' ? 'pro' : 'simple')}>
            <SlidersHorizontal size={18} />
            {uiMode === 'simple' ? '切换到高级模式' : '返回基础模式'}
          </button>
          <button type="button" className="ghost-button" onClick={() => setActiveView(uiMode === 'simple' ? 'guide' : 'boot')}>
            {uiMode === 'simple' ? <CircleHelp size={18} /> : <Image size={18} />}
            {uiMode === 'simple' ? '查看新手教程' : '直接去开机图'}
          </button>
        </div>
      </section>
    </div>
  )
}

function ChannelEditor({
  data,
  setData,
  addLog,
}: {
  data: AppData
  setData: (updater: (current: AppData) => AppData) => void
  addLog: (line: string) => void
}) {
  const preferredBankIndex = getPreferredBankIndex(data)
  const [manualBankIndex, setManualBankIndex] = useState<number | null>(null)
  const bankIndex = manualBankIndex ?? preferredBankIndex
  const [selectedIndex, setSelectedIndex] = useState(0)
  const [clipboard, setClipboard] = useState<Channel[]>([])
  const [search, setSearch] = useState('')
  const [showEmpty, setShowEmpty] = useState(false)
  const [showTips, setShowTips] = useState(true)
  const [showRepeaterLibrary, setShowRepeaterLibrary] = useState(false)
  const [repeaterPackage, setRepeaterPackage] = useState<RepeaterLibraryPackage | null>(null)
  const [repeaterLoading, setRepeaterLoading] = useState(false)
  const [repeaterError, setRepeaterError] = useState('')
  const [repeaterRegion, setRepeaterRegion] = useState('')
  const [repeaterProvinceCode, setRepeaterProvinceCode] = useState<number | null>(null)
  const [repeaterCityCode, setRepeaterCityCode] = useState<number | null>(null)
  const [repeaterQuery, setRepeaterQuery] = useState('')
  const [repeaterVisibleLimit, setRepeaterVisibleLimit] = useState(80)
  const [selectedRepeaterId, setSelectedRepeaterId] = useState('')
  const bank = data.channels[bankIndex]
  const selected = bank[selectedIndex]
  const visibleCount = bank.filter((channel) => channel.visible && channel.rxFreq).length
  const fieldTips = {
    rxFreq: '你要接收的频率。格式例子：145.50000。',
    txFreq: '你按下发射键时发出去的频率。不确定时，先填和接收频率一样。',
    rxTone: '只有收到带这个亚音的信号才会开静噪。不知道就先选 OFF。',
    txTone: '发射时附带的亚音。很多中继台会要求这里有值，不知道就先按资料填写。',
    name: '显示在手台上的信道名称，尽量短一点。',
  }
  const filteredChannels = bank.filter((channel) => {
    if (!showEmpty && !channel.visible && !channel.rxFreq) return false
    const keyword = search.trim().toLowerCase()
    if (!keyword) return true
    return [channel.name, channel.rxFreq, channel.txFreq, `ch-${channel.id}`].join(' ').toLowerCase().includes(keyword)
  })
  const repeaterRegions = useMemo(() => repeaterPackage?.regions ?? [], [repeaterPackage])
  const repeaterEntries = useMemo(() => repeaterPackage?.repeaters ?? [], [repeaterPackage])
  const activeRegionName = repeaterRegion || repeaterRegions[0]?.label || ''
  const activeRegion = repeaterRegions.find((region) => region.label === activeRegionName)
  const activeProvinces = activeRegion?.children ?? []
  const regionRepeaters = useMemo(
    () => repeaterEntries.filter((entry) => !activeRegionName || entry.region === activeRegionName),
    [activeRegionName, repeaterEntries],
  )
  const areaRepeaters = useMemo(
    () =>
      regionRepeaters.filter((entry) => {
        if (repeaterProvinceCode !== null && entry.provinceCode !== repeaterProvinceCode) return false
        if (repeaterCityCode !== null && entry.cityCode !== repeaterCityCode) return false
        return true
      }),
    [regionRepeaters, repeaterCityCode, repeaterProvinceCode],
  )
  const cityOptions = useMemo(() => {
    const cityMap = new Map<number, { code: number; name: string; count: number }>()
    regionRepeaters.forEach((entry) => {
      if (repeaterProvinceCode !== null && entry.provinceCode !== repeaterProvinceCode) return
      const current = cityMap.get(entry.cityCode) ?? { code: entry.cityCode, name: entry.city, count: 0 }
      current.count += 1
      cityMap.set(entry.cityCode, current)
    })
    return [...cityMap.values()].sort((left, right) => left.name.localeCompare(right.name, 'zh-Hans-CN'))
  }, [regionRepeaters, repeaterProvinceCode])
  const filteredRepeaters = useMemo(() => {
    const keyword = repeaterQuery.trim().toLowerCase()
    if (!keyword) return areaRepeaters
    return areaRepeaters.filter((entry) =>
      [entry.region, entry.province, entry.city, entry.area, entry.name, entry.callSign, describeRepeater(entry), entry.kind, entry.remark]
        .join(' ')
        .toLowerCase()
        .includes(keyword),
    )
  }, [areaRepeaters, repeaterQuery])
  const visibleRepeaters = filteredRepeaters.slice(0, repeaterVisibleLimit)
  const selectedRepeater = filteredRepeaters.find((entry) => entry.id === selectedRepeaterId) ?? filteredRepeaters[0] ?? null

  function updateSelected(patch: Partial<Channel>) {
    setData((current) => {
      const next = cloneAppData(current)
      next.channels[bankIndex][selectedIndex] = {
        ...next.channels[bankIndex][selectedIndex],
        ...patch,
        visible: Boolean((patch.rxFreq ?? next.channels[bankIndex][selectedIndex].rxFreq) || patch.visible),
      }
      next.updatedAt = new Date().toISOString()
      return next
    })
  }

  function updateBankName(value: string) {
    setData((current) => {
      const next = cloneAppData(current)
      next.bankNames[bankIndex] = value.slice(0, 12)
      return next
    })
  }

  function copyChannel() {
    setClipboard([cloneChannel(selected)])
    addLog(`已复制 ${data.bankNames[bankIndex]} / CH-${selected.id}`)
  }

  function cutChannel() {
    setClipboard([cloneChannel(selected)])
    clearChannel()
  }

  function pasteChannel() {
    if (!clipboard.length) return
    setData((current) => {
      const next = cloneAppData(current)
      clipboard.forEach((channel, offset) => {
        const index = selectedIndex + offset
        if (index < 64) next.channels[bankIndex][index] = { ...cloneChannel(channel), id: index + 1 }
      })
      return next
    })
  }

  function clearChannel() {
    setData((current) => {
      const next = cloneAppData(current)
      next.channels[bankIndex][selectedIndex] = createEmptyChannel(selectedIndex + 1)
      return next
    })
  }

  function deleteChannel() {
    setData((current) => {
      const next = cloneAppData(current)
      for (let index = selectedIndex; index < 63; index += 1) {
        next.channels[bankIndex][index] = { ...next.channels[bankIndex][index + 1], id: index + 1 }
      }
      next.channels[bankIndex][63] = createEmptyChannel(64)
      return next
    })
  }

  function insertChannel() {
    setData((current) => {
      const next = cloneAppData(current)
      if (next.channels[bankIndex][63].visible) return next
      for (let index = 63; index > selectedIndex; index -= 1) {
        next.channels[bankIndex][index] = { ...next.channels[bankIndex][index - 1], id: index + 1 }
      }
      next.channels[bankIndex][selectedIndex] = createEmptyChannel(selectedIndex + 1)
      return next
    })
  }

  function compactBank() {
    setData((current) => {
      const next = cloneAppData(current)
      const used = next.channels[bankIndex].filter((channel) => channel.visible && channel.rxFreq)
      next.channels[bankIndex] = Array.from({ length: 64 }, (_, index) =>
        used[index] ? { ...used[index], id: index + 1 } : createEmptyChannel(index + 1),
      )
      return next
    })
  }

  function applyRepeater(entry: RepeaterEntry) {
    setSelectedRepeaterId(entry.id)
    setData((current) => {
      const next = cloneAppData(current)
      next.channels[bankIndex][selectedIndex] = buildChannelFromRepeater(entry, selectedIndex + 1)
      next.updatedAt = new Date().toISOString()
      return next
    })
    addLog(`已将中继台写入 ${data.bankNames[bankIndex]} / CH-${selectedIndex + 1}：${entry.city}${entry.name}${entry.callSign ? entry.callSign : ''}`)
  }

  function resetRepeaterList() {
    setRepeaterVisibleLimit(80)
  }

  function ensureRepeaterLibrary() {
    if (repeaterPackage || repeaterLoading) return
    setRepeaterLoading(true)
    setRepeaterError('')
    loadRepeaterLibrary()
      .then((library) => {
        setRepeaterPackage(library)
        setRepeaterRegion((current) => current || library.regions[0]?.label || '')
        setSelectedRepeaterId((current) => current || library.repeaters[0]?.id || '')
      })
      .catch((error: unknown) => {
        const fallback = createFallbackRepeaterPackage()
        setRepeaterPackage(fallback)
        setRepeaterRegion(fallback.regions[0]?.label || '')
        setSelectedRepeaterId(fallback.repeaters[0]?.id || '')
        setRepeaterError(error instanceof Error ? error.message : '中继台库加载失败，已启用内置备用库')
      })
      .finally(() => setRepeaterLoading(false))
  }

  return (
    <div className="channel-page">
      <div className="feature-grid channel-layout">
      <section className="panel bank-panel">
        <div className="panel-heading">
          <div>
            <h3>区域</h3>
            <p>{data.bankNames[bankIndex]} · 已配置 {visibleCount}/64</p>
          </div>
          <input value={data.bankNames[bankIndex]} placeholder="给这组信道起名" onChange={(event) => updateBankName(event.target.value)} />
        </div>
        {showTips ? (
          <div className="beginner-banner">
            <strong>新手建议</strong>
            <span>先改一个信道试试。只填接收频率也能先保存成草稿；需要发射时，再填发射频率和亚音。</span>
          </div>
        ) : null}
        <div className="bank-tabs">
          {data.bankNames.map((name, index) => (
            <button
              key={index}
              type="button"
              className={index === bankIndex ? 'active' : ''}
              onClick={() => {
                setManualBankIndex(index)
                setSelectedIndex(0)
              }}
            >
              <span>{index + 1}</span>
              {name}
            </button>
          ))}
        </div>
        <div className="channel-toolbar">
          <TextField label="搜索信道" value={search} onChange={setSearch} compact />
          <div className="toolbar-toggles">
            <label className="toggle-line">
              <input type="checkbox" checked={showEmpty} onChange={(event) => setShowEmpty(event.target.checked)} />
              显示空信道
            </label>
            <label className="toggle-line">
              <input type="checkbox" checked={showTips} onChange={(event) => setShowTips(event.target.checked)} />
              显示填写提示
            </label>
          </div>
        </div>
        <div className="channel-list">
          {filteredChannels.map((channel) => {
            const index = channel.id - 1
            return (
              <button
                key={channel.id}
                type="button"
                className={`${index === selectedIndex ? 'selected' : ''} ${channel.visible ? 'filled' : ''}`}
                onClick={() => setSelectedIndex(index)}
              >
                <span className="channel-id">CH-{String(channel.id).padStart(2, '0')}</span>
                <div className="channel-main">
                  <strong>{channel.name || '未命名信道'}</strong>
                  <em>{channel.visible ? '已启用' : '草稿 / 空位'}</em>
                </div>
                <div className="channel-freq">
                  <b>{channel.rxFreq || '空信道'}</b>
                  <em>接收</em>
                </div>
                <div className="channel-freq">
                  <b>{channel.txFreq || channel.rxFreq || '尚未配置'}</b>
                  <em>发射</em>
                </div>
              </button>
            )
          })}
          {filteredChannels.length === 0 && <div className="channel-empty">没有匹配的信道</div>}
        </div>
      </section>
      <section className="panel inspector">
        <div className="panel-heading">
          <div>
            <h3>CH-{selected.id}</h3>
            <p>{selected.visible ? '已启用信道' : '空信道'}</p>
          </div>
          <span className={`status-pill ${selected.visible ? 'ok' : ''}`}>{selected.visible ? '可写回' : '未启用'}</span>
        </div>
        {showTips ? (
          <div className="inspector-hint">
            <strong>推荐顺序</strong>
            <span>先填接收频率，再决定发射频率和亚音；只改这几个字段就能完成大多数写频。</span>
          </div>
        ) : null}
        <div className="panel-heading compact-actions">
          <div className="tool-row">
            <button type="button" onClick={copyChannel} title="复制">
              <Copy size={16} />
            </button>
            <button type="button" onClick={cutChannel} title="剪切">
              <Scissors size={16} />
            </button>
            <button type="button" onClick={pasteChannel} title="粘贴">
              <Save size={16} />
            </button>
            <button type="button" onClick={clearChannel} title="清空">
              <Trash2 size={16} />
            </button>
          </div>
        </div>
        <div className="summary-list compact-list">
          <span>区域 <strong>{data.bankNames[bankIndex]}</strong></span>
          <span>接收 <strong>{selected.rxFreq || '空'}</strong></span>
          <span>发射 <strong>{selected.txFreq || selected.rxFreq || '空'}</strong></span>
        </div>
        <div className="form-grid">
          <TextField
            label="接收频率"
            value={selected.rxFreq}
            placeholder="例：145.50000"
            hint={fieldTips.rxFreq}
            onChange={(value) => updateSelected({ rxFreq: sanitizeRadioFrequencyDraft(value) })}
            onBlur={() => updateSelected({ rxFreq: normalizeRadioFrequency(selected.rxFreq) })}
          />
          <TextField
            label="发射频率"
            value={selected.txFreq}
            placeholder="不确定时先填和接收一样"
            hint={fieldTips.txFreq}
            onChange={(value) => updateSelected({ txFreq: sanitizeRadioFrequencyDraft(value) })}
            onBlur={() => updateSelected({ txFreq: normalizeRadioFrequency(selected.txFreq) })}
          />
          <SelectField label="接收亚音" value={selected.rxTone} options={TONE_CHOICES} hint={fieldTips.rxTone} onChange={(value) => updateSelected({ rxTone: value })} />
          <SelectField label="发射亚音" value={selected.txTone} options={TONE_CHOICES} hint={fieldTips.txTone} onChange={(value) => updateSelected({ txTone: value })} />
          <SelectIndex label="功率" value={selected.txPower} options={CHANNEL_CHOICES.power} hint="发射强度。不懂就先保持默认。" onChange={(value) => updateSelected({ txPower: value })} />
          <SelectIndex label="带宽" value={selected.bandwidth} options={CHANNEL_CHOICES.bandwidth} hint="一般先保持默认，除非明确知道要改。" onChange={(value) => updateSelected({ bandwidth: value })} />
          <SelectIndex label="扫描加入" value={selected.scanAdd} options={CHANNEL_CHOICES.scanAdd} hint="决定这个信道是否参与扫描。" onChange={(value) => updateSelected({ scanAdd: value })} />
          <SelectIndex label="繁忙锁" value={selected.busyLock} options={CHANNEL_CHOICES.busyLock} hint="避免频率上有人时强行发射。" onChange={(value) => updateSelected({ busyLock: value })} />
          <SelectIndex label="PTT-ID" value={selected.pttid} options={CHANNEL_CHOICES.pttid} hint="需要 DTMF 发码时再设置，不懂就默认。" onChange={(value) => updateSelected({ pttid: value })} />
          <SelectIndex label="信令组" value={selected.signalGroup} options={CHANNEL_CHOICES.signalGroup} hint="配合选呼信令用，不懂就默认。" onChange={(value) => updateSelected({ signalGroup: value })} />
          <TextField label="信道名称" value={selected.name} placeholder="例：本地中继" hint={fieldTips.name} onChange={(value) => updateSelected({ name: value.slice(0, 12) })} />
        </div>
        <div className="batch-row">
          <button type="button" className="ghost-button" onClick={insertChannel}>插入</button>
          <button type="button" className="ghost-button" onClick={deleteChannel}>删除并上移</button>
          <button type="button" className="ghost-button" onClick={compactBank}>整理空信道</button>
        </div>
      </section>
      </div>
      <section className="panel repeater-panel wide">
        <button
          type="button"
          className="repeater-toggle"
          onClick={() => {
            const nextVisible = !showRepeaterLibrary
            setShowRepeaterLibrary(nextVisible)
            if (nextVisible) ensureRepeaterLibrary()
          }}
        >
          <div>
            <strong>全国中继台库</strong>
            <span>按大区、省份和城市快速筛选，选择后可一键写入当前信道。</span>
          </div>
          <div className="repeater-toggle-meta">
            <span>{repeaterPackage ? `${repeaterPackage.total} 条 · ${repeaterPackage.source}` : 'HamCQ 数据库'}</span>
            <em>{showRepeaterLibrary ? '收起' : '展开'}</em>
          </div>
        </button>
        {showRepeaterLibrary ? (
          <div className="repeater-database">
            <div className="repeater-toolbar">
              <TextField
                label="搜索中继台"
                value={repeaterQuery}
                placeholder="名称 / 呼号 / 城市 / 频率 / 亚音"
                onChange={(value) => {
                  setRepeaterQuery(value)
                  resetRepeaterList()
                }}
                compact
              />
              <div className="repeater-library-status">
                {repeaterLoading ? <span>正在加载中继台库...</span> : null}
                {!repeaterLoading && repeaterPackage ? (
                  <span>
                    已载入 {repeaterPackage.total} 条，当前筛选 {filteredRepeaters.length} 条
                    {repeaterPackage.fetchedAt ? ` · ${new Date(repeaterPackage.fetchedAt).toLocaleDateString('zh-CN')}` : ''}
                  </span>
                ) : null}
                {repeaterError ? <span className="warning-text">{repeaterError}</span> : null}
              </div>
            </div>
            <div className="repeater-region-strip" aria-label="中继台大区">
              {repeaterRegions.map((region) => (
                <button
                  key={region.label}
                  type="button"
                  className={activeRegionName === region.label ? 'active' : ''}
                  onClick={() => {
                    setRepeaterRegion(region.label)
                    setRepeaterProvinceCode(null)
                    setRepeaterCityCode(null)
                    resetRepeaterList()
                  }}
                >
                  <strong>{region.label}</strong>
                  <span>{region.children.reduce((sum, province) => sum + province.analog_total + province.digi_total, 0)} 条</span>
                </button>
              ))}
            </div>
            <div className="repeater-province-grid">
              <button
                type="button"
                className={repeaterProvinceCode === null ? 'active' : ''}
                onClick={() => {
                  setRepeaterProvinceCode(null)
                  setRepeaterCityCode(null)
                  resetRepeaterList()
                }}
              >
                <strong>全区</strong>
                <span>{regionRepeaters.length} 条中继</span>
              </button>
              {activeProvinces.map((province) => (
                <button
                  key={province.code}
                  type="button"
                  className={repeaterProvinceCode === province.code ? 'active' : ''}
                  onClick={() => {
                    setRepeaterProvinceCode(province.code)
                    setRepeaterCityCode(null)
                    resetRepeaterList()
                  }}
                >
                  <strong>{province.name}</strong>
                  <span>模拟 {province.analog_total} · 数字 {province.digi_total}</span>
                </button>
              ))}
            </div>
            <div className="repeater-city-strip" aria-label="中继台城市">
              <button
                type="button"
                className={repeaterCityCode === null ? 'active' : ''}
                onClick={() => {
                  setRepeaterCityCode(null)
                  resetRepeaterList()
                }}
              >
                全部城市
              </button>
              {cityOptions.map((city) => (
                <button
                  key={city.code}
                  type="button"
                  className={repeaterCityCode === city.code ? 'active' : ''}
                  onClick={() => {
                    setRepeaterCityCode(city.code)
                    resetRepeaterList()
                  }}
                >
                  {city.name}
                  <span>{city.count}</span>
                </button>
              ))}
            </div>
            <div className="repeater-content">
              <div className="repeater-list">
                {visibleRepeaters.map((entry) => (
                  <button key={entry.id} type="button" className={selectedRepeater?.id === entry.id ? 'selected' : ''} onClick={() => setSelectedRepeaterId(entry.id)}>
                    <div className="repeater-head">
                      <strong>{entry.name}{entry.callSign ? ` ${entry.callSign}` : ''}</strong>
                      <span>{entry.province} · {entry.city}</span>
                    </div>
                    <div className="repeater-meta">
                      <b className={`kind-badge ${entry.kind}`}>{entry.kind}</b>
                      <em>{describeRepeater(entry)}</em>
                    </div>
                    {entry.remark ? <p>{entry.remark}</p> : null}
                  </button>
                ))}
                {filteredRepeaters.length === 0 && !repeaterLoading ? <div className="channel-empty">没有匹配的中继台</div> : null}
                {visibleRepeaters.length < filteredRepeaters.length ? (
                  <button type="button" className="repeater-load-more" onClick={() => setRepeaterVisibleLimit((current) => current + 80)}>
                    加载更多 · 还有 {filteredRepeaters.length - visibleRepeaters.length} 条
                  </button>
                ) : null}
              </div>
              {selectedRepeater ? (
                <aside className="repeater-preview">
                  <div>
                    <strong>{selectedRepeater.name}{selectedRepeater.callSign ? ` ${selectedRepeater.callSign}` : ''}</strong>
                    <span>{selectedRepeater.province} · {selectedRepeater.city} · {selectedRepeater.updatedAt || '未知更新时间'}</span>
                  </div>
                  <div className="summary-list compact-list">
                    <span>接收 <strong>{selectedRepeater.rxFreq}</strong></span>
                    <span>发射 <strong>{buildChannelFromRepeater(selectedRepeater, selected.id).txFreq}</strong></span>
                    <span>亚音 <strong>{buildChannelFromRepeater(selectedRepeater, selected.id).rxTone}/{buildChannelFromRepeater(selectedRepeater, selected.id).txTone}</strong></span>
                    <span>模式 <strong>{selectedRepeater.mode && selectedRepeater.mode !== '0' ? selectedRepeater.mode : selectedRepeater.kind}</strong></span>
                  </div>
                  <button type="button" className="primary-button" onClick={() => applyRepeater(selectedRepeater)}>
                    <Upload size={18} />
                    写入当前信道 CH-{selected.id}
                  </button>
                </aside>
              ) : (
                <aside className="repeater-preview muted-preview">
                  <strong>请选择中继台</strong>
                  <span>加载数据库后，先选大区、省份或城市，再把需要的中继台写入当前信道。</span>
                </aside>
              )}
            </div>
          </div>
        ) : (
          <div className="repeater-compact-hint">
            <div>
              <strong>数据来源</strong>
              <span>使用 HamCQ 中继台数据，展开后再加载，避免影响主页面打开速度。</span>
            </div>
          </div>
        )}
      </section>
    </div>
  )
}

function VfoPanel({ data, setData }: DataPanelProps) {
  const vfoFields = [
    { key: 'vfoAFreq', label: 'A 频率', type: 'text' },
    { key: 'vfoARxTone', label: 'A 接收亚音', type: 'tone' },
    { key: 'vfoATxTone', label: 'A 发射亚音', type: 'tone' },
    { key: 'vfoATxPower', label: 'A 功率', type: 'power' },
    { key: 'vfoAScramble', label: 'A 加扰', type: 'scramble' },
    { key: 'vfoABandwidth', label: 'A 带宽', type: 'bandwidth' },
    { key: 'vfoAStep', label: 'A 步进', type: 'step' },
    { key: 'vfoABusyLock', label: 'A 繁忙锁', type: 'onoff' },
    { key: 'vfoASignalGroup', label: 'A 信令组', type: 'signal' },
    { key: 'vfoADirection', label: 'A 频偏方向', type: 'direction' },
    { key: 'vfoAOffset', label: 'A 频偏', type: 'text' },
    { key: 'vfoBFreq', label: 'B 频率', type: 'text' },
    { key: 'vfoBRxTone', label: 'B 接收亚音', type: 'tone' },
    { key: 'vfoBTxTone', label: 'B 发射亚音', type: 'tone' },
    { key: 'vfoBTxPower', label: 'B 功率', type: 'power' },
    { key: 'vfoBScramble', label: 'B 加扰', type: 'scramble' },
    { key: 'vfoBBandwidth', label: 'B 带宽', type: 'bandwidth' },
    { key: 'vfoBStep', label: 'B 步进', type: 'step' },
    { key: 'vfoBBusyLock', label: 'B 繁忙锁', type: 'onoff' },
    { key: 'vfoBSignalGroup', label: 'B 信令组', type: 'signal' },
    { key: 'vfoBDirection', label: 'B 频偏方向', type: 'direction' },
    { key: 'vfoBOffset', label: 'B 频偏', type: 'text' },
  ] as const

  function update(key: keyof AppData['vfos'], value: string | number) {
    setData((current) => {
      const next = cloneAppData(current)
      next.vfos = { ...next.vfos, [key]: value }
      next.updatedAt = new Date().toISOString()
      return next
    })
  }

  return (
    <section className="panel">
      <div className="panel-heading">
        <div>
          <h3>频率模式</h3>
          <p>VFO A/B 参数和 PTT-ID</p>
        </div>
        <SelectIndex label="PTT-ID" value={data.vfos.pttid} options={VFO_CHOICES.pttid} onChange={(value) => update('pttid', value)} compact />
      </div>
      <div className="form-grid three">
        {vfoFields.map((field) => (
          <DynamicVfoField key={field.key} field={field} data={data} update={update} />
        ))}
      </div>
    </section>
  )
}

function DynamicVfoField({
  field,
  data,
  update,
}: {
  field: { key: keyof AppData['vfos']; label: string; type: string }
  data: AppData
  update: (key: keyof AppData['vfos'], value: string | number) => void
}) {
  const value = data.vfos[field.key]
  if (field.type === 'tone') return <SelectField label={field.label} value={String(value)} options={TONE_CHOICES} onChange={(next) => update(field.key, next)} />
  if (field.type === 'power') return <SelectIndex label={field.label} value={Number(value)} options={CHANNEL_CHOICES.power} onChange={(next) => update(field.key, next)} />
  if (field.type === 'bandwidth') return <SelectIndex label={field.label} value={Number(value)} options={CHANNEL_CHOICES.bandwidth} onChange={(next) => update(field.key, next)} />
  if (field.type === 'step') return <SelectIndex label={field.label} value={Number(value)} options={VFO_CHOICES.step} onChange={(next) => update(field.key, next)} />
  if (field.type === 'onoff') return <SelectIndex label={field.label} value={Number(value)} options={CHANNEL_CHOICES.busyLock} onChange={(next) => update(field.key, next)} />
  if (field.type === 'signal') return <SelectIndex label={field.label} value={Number(value)} options={CHANNEL_CHOICES.signalGroup} onChange={(next) => update(field.key, next)} />
  if (field.type === 'direction') return <SelectIndex label={field.label} value={Number(value)} options={VFO_CHOICES.direction} onChange={(next) => update(field.key, next)} />
  if (field.type === 'scramble') return <SelectIndex label={field.label} value={Number(value)} options={VFO_CHOICES.scramble} onChange={(next) => update(field.key, next)} />
  return <TextField label={field.label} value={String(value)} onChange={(next) => update(field.key, next)} />
}

const settingFields: Array<{ key: keyof FunctionSettings; label: string; options: readonly string[] }> = [
  { key: 'sql', label: '静噪等级', options: FUNCTION_CHOICES.sql },
  { key: 'tot', label: '发射限时', options: FUNCTION_CHOICES.txTimeout },
  { key: 'saveMode', label: '省电模式', options: FUNCTION_CHOICES.saveMode },
  { key: 'voxSwitch', label: 'VOX 开关', options: FUNCTION_CHOICES.onOff },
  { key: 'vox', label: 'VOX 等级', options: FUNCTION_CHOICES.vox },
  { key: 'voxDelay', label: 'VOX 延迟', options: FUNCTION_CHOICES.voxDelay },
  { key: 'dualStandby', label: '双守', options: FUNCTION_CHOICES.onOff },
  { key: 'tone', label: '倒频音', options: FUNCTION_CHOICES.tone },
  { key: 'sideTone', label: '侧音', options: FUNCTION_CHOICES.sideTone },
  { key: 'tailClear', label: '尾音消除', options: FUNCTION_CHOICES.onOff },
  { key: 'powerOnDisplay', label: '开机显示', options: FUNCTION_CHOICES.powerOnDisplay },
  { key: 'beep', label: '提示音', options: FUNCTION_CHOICES.onOff },
  { key: 'micGain', label: '麦克风增益', options: FUNCTION_CHOICES.micGain },
  { key: 'scanMode', label: '扫描模式', options: FUNCTION_CHOICES.scanMode },
  { key: 'alarmMode', label: '报警模式', options: FUNCTION_CHOICES.sos },
  { key: 'keyLock', label: '键盘锁', options: FUNCTION_CHOICES.onOff },
  { key: 'fmEnable', label: 'FM', options: FUNCTION_CHOICES.fm },
  { key: 'autoLock', label: '自动锁时间', options: FUNCTION_CHOICES.autoLock },
  { key: 'menuQuitTime', label: '菜单退出', options: FUNCTION_CHOICES.autoQuit },
  { key: 'backlight', label: '背光时间', options: FUNCTION_CHOICES.backlight },
  { key: 'voice', label: '语音提示', options: FUNCTION_CHOICES.onOff },
  { key: 'pttDelay', label: '发码延迟', options: FUNCTION_CHOICES.pttDelay },
  { key: 'roger', label: '发射结束音', options: FUNCTION_CHOICES.onOff },
  { key: 'localSosTone', label: '本机 SOS 音', options: FUNCTION_CHOICES.onOff },
  { key: 'currentBankA', label: 'A 区域', options: FUNCTION_CHOICES.bank },
  { key: 'currentBankB', label: 'B 区域', options: FUNCTION_CHOICES.bank },
  { key: 'chADisplay', label: 'A 显示', options: FUNCTION_CHOICES.displayType },
  { key: 'chBDisplay', label: 'B 显示', options: FUNCTION_CHOICES.displayType },
  { key: 'chAWorkmode', label: 'A 工作模式', options: FUNCTION_CHOICES.workMode },
  { key: 'chBWorkmode', label: 'B 工作模式', options: FUNCTION_CHOICES.workMode },
  { key: 'key2Short', label: '侧键短按', options: FUNCTION_CHOICES.keyFunc },
  { key: 'key2Long', label: '侧键长按', options: FUNCTION_CHOICES.keyFunc },
  { key: 'rptTailClear', label: '中继尾音消除', options: FUNCTION_CHOICES.rptTail },
  { key: 'rptTailDetect', label: '中继尾音检测', options: FUNCTION_CHOICES.rptTail },
  { key: 'powerOnDelay', label: '开机图时长', options: FUNCTION_CHOICES.powerUpDisplayTime },
  { key: 'bluetoothAudioGain', label: '蓝牙语音增益', options: FUNCTION_CHOICES.gain5 },
  { key: 'bluetoothMicGain', label: '蓝牙麦克风增益', options: FUNCTION_CHOICES.gain5 },
]

const settingGroups: Array<{
  title: string
  description: string
  keys: Array<keyof FunctionSettings>
}> = [
  {
    title: '收发与音频',
    description: '静噪、麦克风、提示音、语音和蓝牙音频',
    keys: ['sql', 'micGain', 'beep', 'voice', 'sideTone', 'tone', 'bluetoothAudioGain', 'bluetoothMicGain'],
  },
  {
    title: '省电与显示',
    description: '背光、开机显示、菜单退出和自动锁',
    keys: ['saveMode', 'backlight', 'powerOnDisplay', 'powerOnDelay', 'menuQuitTime', 'autoLock', 'keyLock'],
  },
  {
    title: '扫描与守候',
    description: '扫描模式、双守、尾音处理和 FM',
    keys: ['scanMode', 'dualStandby', 'tailClear', 'rptTailClear', 'rptTailDetect', 'fmEnable', 'roger'],
  },
  {
    title: '发射与功能键',
    description: '发射限时、VOX、报警和快捷键',
    keys: ['tot', 'voxSwitch', 'vox', 'voxDelay', 'pttDelay', 'alarmMode', 'localSosTone', 'key2Short', 'key2Long'],
  },
  {
    title: '双段与区域',
    description: 'A/B 区域、显示模式和工作模式',
    keys: ['currentBankA', 'currentBankB', 'chADisplay', 'chBDisplay', 'chAWorkmode', 'chBWorkmode'],
  },
]

function SettingsPanel({ data, setData }: DataPanelProps) {
  const [search, setSearch] = useState('')
  const [saveState, setSaveState] = useState('自动保存到当前配置')
  const [showTips, setShowTips] = useState(false)

  const settingTips: Record<string, string> = {
    '收发与音频': '这一组主要影响你听到什么、别人听到你时的音量和提示音表现。新手一般只会碰静噪、提示音和语音提示。',
    '省电与显示': '这一组决定屏幕、开机显示和锁键体验。除非你明确不喜欢当前显示方式，否则可以只微调背光和自动锁。',
    '扫描与守候': '这里是扫描、双守和 FM 相关设置。双守适合同时盯两个频点，FM 是广播收音机，不是业余通联模式。',
    '发射与功能键': '这里是发射时限、VOX 和快捷键。VOX 是声音触发发射，不熟悉时建议关闭。',
    '双段与区域': '这里控制 A/B 双段当前显示哪个区域、以信道还是频率模式工作。看不到你写进去的信道时，先检查这里。',
  }

  function update(key: keyof FunctionSettings, value: number | string) {
    setData((current) => {
      const next = cloneAppData(current)
      next.functions = { ...next.functions, [key]: value }
      next.updatedAt = new Date().toISOString()
      return next
    })
    setSaveState('已修改，当前配置已更新')
  }

  function updatePttId(value: number) {
    setData((current) => {
      const next = cloneAppData(current)
      next.vfos = { ...next.vfos, pttid: value }
      next.updatedAt = new Date().toISOString()
      return next
    })
    setSaveState('已修改，当前配置已更新')
  }

  async function saveCurrentSettings() {
    await saveBackup(data, '功能设置手动保存')
    setSaveState('已手动保存一份备份')
  }

  const keyword = search.trim().toLowerCase()
  const groupedFields = settingGroups.map((group) => ({
    ...group,
    fields: group.keys
      .map((key) => settingFields.find((field) => field.key === key))
      .filter((field): field is NonNullable<typeof field> => Boolean(field))
      .filter((field) => !keyword || `${field.label} ${group.title} ${group.description}`.toLowerCase().includes(keyword)),
  }))
  const hasMatches = groupedFields.some((group) => group.fields.length > 0)

  return (
    <section className="panel">
      <div className="panel-heading">
        <div>
          <h3>功能设置</h3>
          <p>按主题分组查看整机设置，改动会立即写入当前配置；点“保存备份”可以额外留一份恢复点。</p>
        </div>
        <div className="settings-topbar">
          <TextField label="搜索设置" value={search} onChange={setSearch} compact />
          <TextField label="呼号" value={data.functions.callSign} onChange={(value) => update('callSign', value.toUpperCase().replace(/[^0-9A-Z]/g, '').slice(0, 6))} compact />
          <SelectIndex label="PTT-ID" value={data.vfos.pttid} options={VFO_CHOICES.pttid} onChange={updatePttId} compact />
          <label className="toggle-line">
            <input type="checkbox" checked={showTips} onChange={(event) => setShowTips(event.target.checked)} />
            显示设置说明
          </label>
          <button type="button" className="ghost-button" onClick={() => void saveCurrentSettings()}>
            <Save size={18} />
            保存备份
          </button>
        </div>
      </div>
      <p className="inline-note">{saveState}</p>
      <div className="settings-groups">
        {groupedFields.map((group) => {
          if (group.fields.length === 0) return null

          return (
            <section key={group.title} className="settings-group">
              <div className="settings-group-head">
                <h4>{group.title}</h4>
                <p>{group.description}</p>
              </div>
              {showTips ? (
                <div className="inline-help">
                  <strong>{group.title}怎么用</strong>
                  <span>{settingTips[group.title]}</span>
                </div>
              ) : null}
              <div className="form-grid four">
                {group.fields.map((field) => (
                  <SelectIndex
                    key={field.key}
                    label={field.label}
                    value={Number(data.functions[field.key]) || 0}
                    options={field.options}
                    onChange={(value) => update(field.key, value)}
                  />
                ))}
              </div>
            </section>
          )
        })}
        {!hasMatches && <div className="channel-empty">没有匹配的设置项</div>}
      </div>
    </section>
  )
}

function DtmfPanel({ data, setData }: DataPanelProps) {
  const [showTips, setShowTips] = useState(false)
  const dtmfTips = {
    group: '这一组就是一串按键码。常见用途是选呼、遥控或中继台联动，不会用就先留空。',
    localId: '本机身份码。对方设备或中继需要识别你时才会用到。',
    pttid: '决定按下或松开发射键时，要不要自动发送身份码。',
    wordTime: '每个按键音发送多久。对接老设备时过短可能识别不稳。',
    idleTime: '每个按键音之间的间隔。一般保持默认更稳。',
  }
  function updateGroup(index: number, value: string) {
    setData((current) => {
      const next = cloneAppData(current)
      next.dtmf.groups[index] = value.toUpperCase().replace(/[^0-9ABCD*#]/g, '').slice(0, 6)
      next.updatedAt = new Date().toISOString()
      return next
    })
  }
  function update(key: keyof AppData['dtmf'], value: string | number) {
    setData((current) => {
      const next = cloneAppData(current)
      next.dtmf = { ...next.dtmf, [key]: value }
      next.updatedAt = new Date().toISOString()
      return next
    })
  }
  return (
    <div className="feature-grid">
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h3>DTMF 组</h3>
            <p>15 组呼叫码，支持 0-9 / A-D / * / #</p>
          </div>
          <label className="toggle-line">
            <input type="checkbox" checked={showTips} onChange={(event) => setShowTips(event.target.checked)} />
            显示填写提示
          </label>
        </div>
        {showTips ? (
          <div className="beginner-banner">
            <strong>新手建议</strong>
            <span>如果你只是普通通联，DTMF 可以先不填。只有在选呼、遥控或某些中继规则明确要求时再设置。</span>
          </div>
        ) : null}
        <div className="dtmf-grid">
          {data.dtmf.groups.map((group, index) => (
            <TextField key={index} label={`组 ${index + 1}`} value={group} hint={showTips ? dtmfTips.group : undefined} onChange={(value) => updateGroup(index, value)} />
          ))}
        </div>
      </section>
      <section className="panel inspector">
        <h3>本机 ID</h3>
        <div className="form-grid">
          <TextField label="本机 ID" value={data.dtmf.localId} hint={showTips ? dtmfTips.localId : undefined} onChange={(value) => update('localId', value.toUpperCase().replace(/[^0-9ABCD*#]/g, '').slice(0, 6))} />
          <SelectIndex label="发送 ID" value={data.dtmf.pttid} options={DTMF_CHOICES.sendId} hint={showTips ? dtmfTips.pttid : undefined} onChange={(value) => update('pttid', value)} />
          <SelectIndex label="字码持续" value={data.dtmf.wordTime} options={DTMF_CHOICES.time} hint={showTips ? dtmfTips.wordTime : undefined} onChange={(value) => update('wordTime', value)} />
          <SelectIndex label="字码间隔" value={data.dtmf.idleTime} options={DTMF_CHOICES.time} hint={showTips ? dtmfTips.idleTime : undefined} onChange={(value) => update('idleTime', value)} />
        </div>
      </section>
    </div>
  )
}

function FmPanel({ data, setData }: DataPanelProps) {
  const [showTips, setShowTips] = useState(false)
  const [currentDraft, setCurrentDraft] = useState(() => formatFmDraft(data.fm.currentFreq))
  const [channelDrafts, setChannelDrafts] = useState(() => data.fm.channels.map(formatFmDraft))

  function commitCurrent(value: string) {
    const parsed = parseFmDraft(value)
    const nextValue = parsed ?? 0
    setData((current) => {
      const next = cloneAppData(current)
      next.fm.currentFreq = nextValue
      next.updatedAt = new Date().toISOString()
      return next
    })
    setCurrentDraft(formatFmDraft(nextValue))
  }

  function updateChannelDraft(index: number, value: string) {
    const draft = sanitizeFmDraft(value)
    setChannelDrafts((current) => current.map((item, itemIndex) => (itemIndex === index ? draft : item)))
  }

  function commitChannel(index: number, value: string) {
    const parsed = parseFmDraft(value)
    const nextValue = parsed ?? 0
    setData((current) => {
      const next = cloneAppData(current)
      next.fm.channels[index] = nextValue
      next.updatedAt = new Date().toISOString()
      return next
    })
    setChannelDrafts((current) => current.map((item, itemIndex) => (itemIndex === index ? formatFmDraft(nextValue) : item)))
  }

  return (
    <section className="panel">
      <div className="panel-heading">
        <div>
          <h3>FM 收音机</h3>
          <p>单位显示为 MHz，写入时转换为原机 10kHz 标度</p>
        </div>
        <div className="settings-topbar">
          <label className="toggle-line">
            <input type="checkbox" checked={showTips} onChange={(event) => setShowTips(event.target.checked)} />
            显示填写提示
          </label>
          <TextField
            label="当前频率"
            value={currentDraft}
            onChange={(value) => setCurrentDraft(sanitizeFmDraft(value))}
            onBlur={() => commitCurrent(currentDraft)}
            compact
          />
        </div>
      </div>
      {showTips ? (
        <div className="beginner-banner">
          <strong>FM 是什么</strong>
          <span>这里是广播收音机记忆频道，不是业余无线电通联信道。通常填当地电台频率，比如 87.8、89.3 这类数字。</span>
        </div>
      ) : null}
      <div className="fm-grid">
        {channelDrafts.map((freq, index) => (
          <TextField
            key={index}
            label={`FM ${index + 1}`}
            value={freq}
            hint={showTips ? '填写广播频率，单位 MHz，例如 88.7。' : undefined}
            onChange={(value) => updateChannelDraft(index, value)}
            onBlur={() => commitChannel(index, freq)}
          />
        ))}
      </div>
    </section>
  )
}

function BootImagePanel({
  data,
  setData,
  addLog,
  canWrite,
  busy,
  transportKind,
  onWrite,
}: DataPanelProps & {
  addLog: (line: string) => void
  canWrite: boolean
  busy: boolean
  transportKind?: RadioTransport['kind']
  onWrite: () => void
}) {
  async function handleImage(file: File | undefined) {
    if (!file) return
    const result = await loadBootImage(file)
    setData((current) => ({
      ...cloneAppData(current),
      bootImage: {
        name: file.name,
        width: SHX8800PRO.bootImageWidth,
        height: SHX8800PRO.bootImageHeight,
        dataUrl: result.dataUrl,
        rgb565: result.rgb565,
      },
      updatedAt: new Date().toISOString(),
    }))
    addLog(`开机图已转换为 RGB565：${result.rgb565.length} bytes`)
  }
  return (
    <div className="feature-grid">
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h3>开机图</h3>
            <p>上传任意图片，浏览器裁切为 128×128 并转为 RGB565</p>
          </div>
          <label className="file-button">
            <Image size={18} />
            选择图片
            <input type="file" accept="image/*" onChange={(event) => void handleImage(event.target.files?.[0])} />
          </label>
        </div>
        <div className="boot-preview">
          {data.bootImage?.dataUrl ? <img src={data.bootImage.dataUrl} alt="开机图预览" /> : <span>128×128</span>}
        </div>
      </section>
      <section className="panel inspector">
        <h3>写入策略</h3>
        <p className="muted">USB 会使用 8800Pro 新版图片协议写入。蓝牙写开机图正在开发中，请使用写频线。</p>
        <div className="summary-list">
          <span>尺寸 <strong>{SHX8800PRO.bootImageWidth}×{SHX8800PRO.bootImageHeight}</strong></span>
          <span>格式 <strong>RGB565 LE</strong></span>
          <span>数据 <strong>{data.bootImage?.rgb565?.length ?? 0} bytes</strong></span>
          <span>链路 <strong>{transportKind === 'bluetooth' ? '蓝牙' : transportKind === 'serial' ? 'USB' : '未连接'}</strong></span>
        </div>
        <button type="button" className="primary-button warn" onClick={onWrite} disabled={busy || !canWrite}>
          <Upload size={18} />
          写入开机图
        </button>
      </section>
    </div>
  )
}

function SatellitePanel({ setData, addLog }: DataPanelProps & { addLog: (line: string) => void }) {
  const [modes, setModes] = useState<SatelliteMode[]>([])
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState<SatelliteMode | null>(null)
  const [doppler, setDoppler] = useState(true)
  const [showTips, setShowTips] = useState(false)
  const filtered = modes.filter((mode) => `${mode.name} ${mode.mode}`.toLowerCase().includes(query.toLowerCase())).slice(0, 80)

  async function load() {
    const next = await fetchSatelliteModes()
    setModes(next)
    addLog(`卫星数据已更新：${next.length} 条模式`)
  }

  function insertSelected() {
    if (!selected) return
    const channels = createSatelliteChannels(selected, { doppler, uStep: 2, vStep: 1 })
    setData((current) => {
      const next = cloneAppData(current)
      const bank = next.channels[0]
      channels.forEach((channel) => {
        const emptyIndex = bank.findIndex((item) => !item.visible)
        if (emptyIndex >= 0) bank[emptyIndex] = { ...channel, id: emptyIndex + 1 }
      })
      next.updatedAt = new Date().toISOString()
      return next
    })
    addLog(`已插入卫星信道：${selected.name}`)
  }

  return (
    <div className="feature-grid satellite-layout">
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h3>打星助手</h3>
            <p>来自 amateur-satellite-database，支持多普勒生成 5 条信道</p>
          </div>
          <div className="settings-topbar">
            <label className="toggle-line">
              <input type="checkbox" checked={showTips} onChange={(event) => setShowTips(event.target.checked)} />
              显示说明
            </label>
            <button type="button" className="primary-button" onClick={() => void load()}>
              <RotateCcw size={18} />
              更新星历
            </button>
          </div>
        </div>
        {showTips ? (
          <div className="beginner-banner">
            <strong>打星是什么</strong>
            <span>打星就是通过业余卫星中继通联。这里会把卫星的上行、下行和多普勒偏移拆成几条信道，方便你在通联时切换。</span>
          </div>
        ) : null}
        <TextField label="搜索卫星或模式" value={query} onChange={setQuery} />
        <div className="sat-list">
          {filtered.map((mode, index) => (
            <button key={`${mode.name}-${mode.mode}-${index}`} type="button" className={selected === mode ? 'selected' : ''} onClick={() => setSelected(mode)}>
              <strong>{mode.name}</strong>
              <span>{mode.mode || '未标注模式'}</span>
            </button>
          ))}
        </div>
      </section>
      <section className="panel inspector">
        <h3>{selected?.name ?? '选择一个卫星模式'}</h3>
        {selected ? (
          <>
            <div className="summary-list">
              <span>上行 <strong>{selected.uplink || '-'}</strong></span>
              <span>下行 <strong>{selected.downlink || '-'}</strong></span>
              <span>亚音 <strong>{selected.tone || 'OFF'}</strong></span>
              <span>状态 <strong>{selected.status || '-'}</strong></span>
            </div>
            <label className="switch-line">
              <input type="checkbox" checked={doppler} onChange={(event) => setDoppler(event.target.checked)} />
              生成多普勒 A1/A2/中心/L1/L2
            </label>
            <button type="button" className="primary-button" onClick={insertSelected}>
              <Sparkles size={18} />
              插入到区域一
            </button>
          </>
        ) : (
          <p className="muted">先更新星历，然后选择一个模式。</p>
        )}
      </section>
    </div>
  )
}

function FilesPanel({
  data,
  setData,
  setBaselineData,
  backups,
  refreshBackups,
  addLog,
  diffSummary,
  onOpenDiff,
}: DataPanelProps & {
  setBaselineData: (data: AppData) => void
  backups: BackupRecord[]
  refreshBackups: () => Promise<void>
  addLog: (line: string) => void
  diffSummary: AppDataDiffSummary
  onOpenDiff: () => void
}) {
  async function importJson(file: File | undefined) {
    if (!file) return
    const next = await loadJsonFile(file)
    setData(() => next)
    setBaselineData(cloneAppData(next))
    addLog(`已打开配置：${file.name}`)
  }

  async function importXlsx(file: File | undefined) {
    if (!file) return
    const next = await importExcel(file, data)
    setData(() => next)
    addLog(`已导入 Excel：${file.name}`)
  }

  const latestBackup = backups[0]
  const configuredBanks = data.channels.filter((bank) => bank.some((channel) => channel.visible && channel.rxFreq)).length
  const visibleChannels = countVisibleChannels(data)

  async function saveSnapshot() {
    const record = await saveBackup(data, '手动频率快照')
    await refreshBackups()
    addLog(`已保存频率快照：${record.title}`)
  }

  function restoreSnapshot(backup: BackupRecord) {
    const restored = cloneAppData(backup.data)
    setData(() => restored)
    setBaselineData(cloneAppData(restored))
    addLog(`已恢复频率快照：${backup.reason}`)
  }

  return (
    <div className="feature-grid files-layout">
      <section className="panel snapshot-workbench">
        <div className="panel-heading">
          <div>
            <h3>频率快照</h3>
            <p>把当前 8800Pro 配置保存成一个可恢复的时间点；写频前后、批量导入前都建议手动存一份。</p>
          </div>
          <button type="button" className="primary-button" onClick={() => void saveSnapshot()}>
            <Save size={18} />
            保存快照
          </button>
        </div>
        <div className="snapshot-hero">
          <div>
            <span>当前配置</span>
            <strong>{statsLikeDate(data.updatedAt)}</strong>
            <p>{visibleChannels} 个有效信道，覆盖 {configuredBanks} 个区域；当前与基准有 {diffSummary.totalChanges} 项待写入差异。</p>
          </div>
          <div className="snapshot-metrics">
            <span>快照 <strong>{backups.length}</strong></span>
            <span>最近 <strong>{latestBackup ? statsLikeDate(latestBackup.createdAt) : '暂无'}</strong></span>
          </div>
        </div>
        <div className="beginner-banner">
          <strong>建议流程</strong>
          <span>读频后保存快照，批量导入或写频前再保存快照。写错时恢复快照，再重新写回设备即可。</span>
        </div>
        <div className="action-grid snapshot-actions">
          <button type="button" className="primary-button" onClick={() => downloadJson(data)}>
            <FileDown size={18} />
            导出 JSON
          </button>
          <label className="file-button">
            <FileUp size={18} />
            打开 JSON
            <input type="file" accept=".json,application/json" onChange={(event) => void importJson(event.target.files?.[0])} />
          </label>
          <button type="button" className="primary-button" onClick={() => void exportExcel(data)}>
            <FileSpreadsheet size={18} />
            导出 Excel
          </button>
          <label className="file-button">
            <FileSpreadsheet size={18} />
            导入 Excel
            <input type="file" accept=".xlsx,.xls" onChange={(event) => void importXlsx(event.target.files?.[0])} />
          </label>
          <button type="button" className="ghost-button" onClick={() => exportCsv(data)}>
            导出 CSV
          </button>
          <button type="button" className="ghost-button" onClick={onOpenDiff}>
            <ListChecks size={18} />
            差异对比
          </button>
        </div>
        <DiffSummaryStrip summary={diffSummary} />
      </section>
      <section className="panel snapshot-list-panel">
        <div className="panel-heading">
          <div>
            <h3>快照列表</h3>
            <p>自动快照和手动快照都在这里，恢复后会成为新的基准配置。</p>
          </div>
        </div>
        <div className="backup-list snapshot-list">
          {backups.map((backup) => (
            <article key={backup.id} className="backup-card">
              <div className="backup-main">
                <strong>{backup.reason.replace('备份', '快照')}</strong>
                <span>{new Date(backup.createdAt).toLocaleString()}</span>
                <small>{backup.title}</small>
              </div>
              <div className="backup-actions">
                <button type="button" onClick={() => restoreSnapshot(backup)}>恢复快照</button>
                <button type="button" onClick={() => void deleteBackup(backup.id).then(refreshBackups)}>删除</button>
              </div>
            </article>
          ))}
          {backups.length === 0 && <div className="channel-empty">还没有快照，先读频或点一次“保存快照”。</div>}
        </div>
      </section>
    </div>
  )
}

function GuidePanel({ setActiveView }: { setActiveView: (view: ViewId) => void }) {
  const conceptCards = [
    ['信道', '一个信道就是一组可收可发的无线电参数，最常见的是频率、亚音、功率和名称。'],
    ['区域', '区域可以理解成一个信道分组。你可以按用途来分，比如“本地中继”“车队”“打星”“应急”。'],
    ['区域占用', '表示一个区域里已经配置了多少个信道。比如 12/64，意思是这个区域已经用了 12 个位置。'],
    ['读频', '把手台当前内容读到网页里。第一次操作建议先读频，这样最安全。'],
    ['写频', '把网页里的当前配置写回手台。写之前建议确认备份已经存在。'],
    ['备份', '备份是恢复点。只要写错或试验失败，就能回到之前版本。'],
  ] as const
  const featureCards = [
    ['总览', '看连接状态、区域占用、推荐操作和当前配置概况。'],
    ['信道', '编辑最常用的信道内容，适合日常写频。'],
    ['功能', '调整静噪、背光、VOX、扫描、显示等整机参数。'],
    ['文件', '导入导出 JSON / Excel / CSV，并恢复备份。'],
    ['VFO', '直接调整频率模式下的 A/B 双段参数。'],
    ['DTMF', '配置选呼码、本机 ID 和发码时序。'],
    ['FM', '设置广播收音机记忆频点。'],
    ['开机图', '上传并写入 128×128 开机图。'],
    ['打星', '根据卫星资料生成适合打星的信道组合。'],
    ['日志', '查看连接、读写和校验过程中的详细记录。'],
  ] as const

  return (
    <div className="feature-grid guide-layout">
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h3>新手教程</h3>
            <p>把对讲机里常见但不直观的词先讲清楚，再开始操作会轻松很多。</p>
          </div>
          <button type="button" className="primary-button" onClick={() => setActiveView('channels')}>
            <ListChecks size={18} />
            现在去编辑信道
          </button>
        </div>
        <div className="guide-card-grid">
          {conceptCards.map(([title, text]) => (
            <article key={title} className="guide-card">
              <h4>{title}</h4>
              <p>{text}</p>
            </article>
          ))}
        </div>
      </section>
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h3>网站功能总览</h3>
            <p>先知道每个页面是干什么的，就不会在功能里迷路。</p>
          </div>
        </div>
        <div className="guide-card-grid">
          {featureCards.map(([title, text]) => (
            <article key={title} className="guide-card">
              <h4>{title}</h4>
              <p>{text}</p>
            </article>
          ))}
        </div>
      </section>
    </div>
  )
}

function AboutPanel() {
  return (
    <section className="panel about-panel">
      <div className="about-hero">
        <span>BG7OWW / 8800Pro Web</span>
        <h2>官方之外，目前已知市面上唯一可以完成 8800Pro 蓝牙写频的网页程序</h2>
        <p>它不是一个普通表格编辑器，而是一套在真实手台、官方软件、社区项目和浏览器 API 之间反复校验出来的 8800Pro 专用读写频工具。</p>
      </div>
      <div className="about-copy">
        <p>本项目由BG7OWW制作，旨在通过方便访问的网页让各位HAM们更加方便的操作森海克斯8800Pro的各项功能，部分功能实现来自Github上的开源项目</p>
        <p>如果有任何问题，请联系微信：samaaw1012</p>

        <h4>免责声明</h4>
        <p>本软件仅供技术交流和个人学习使用。任何个人或组织在使用本软件时必须遵守中华人民共和国相关法律法规及无线电管理条例。</p>
        <p>如因使用本软件造成任何损失，包括但不限于数据丢失或设备损坏，作者不承担任何法律责任。数据无价，提醒您注意备份！</p>
        <p>通过下载、安装或使用此软件，您即表示已阅读、理解并同意受项目免责声明的约束。</p>

        <h4>致谢</h4>
        <p>森海克斯官方写频软件</p>
        <p>
          部分功能的实现离不开
          <a href="https://github.com/SydneyOwl/senhaix-freq-writer-enhanced" rel="noreferrer" target="_blank">
            SydneyOwl/senhaix-freq-writer-enhanced
          </a>
        </p>

        <h4>技术实现</h4>
        <p>8800Pro Web 的写频链路不是照着一份完整文档做出来的，而是一步步从开源项目、官方写频软件、APK 行为和真实机器响应里拼出来的。最早只能确定这台机器大概使用森海克斯家族的写频习惯：进入编程模式、按地址读 64 字节内存块、再把同样长度的数据写回。真正困难的是，没有一份公开资料告诉我们每个字段在哪里、蓝牙和写频线是不是同一套协议、哪些字节能改、哪些字节必须保留。</p>
        <p>第一阶段是“找地图”。项目先参考社区开源实现，把信道、VFO、功能设置、DTMF、区域名称和 FM 收音机的大致地址范围标出来；再把每一次 USB 读频得到的原始块保存下来，对照网页里显示的频率、亚音、名称、区域和功能选项，一点点把二进制数据翻译成可编辑字段。频率是 BCD，中文名称是 GB2312，亚音和 DCS 又是另一套编码。看起来只是表单里几个输入框，背后每一个字段都要能往返编码，读出来和写回去必须一致。</p>
        <p>线写频部分相对像“修一条路”：通过 USB 串口反复对照握手、读块、写块和结束指令，确认 `PROGRAMSHXPU`、ACK、`52 addr 40` 读帧、`57 addr 40` 写帧和 64 字节数据区的关系。网页读频时会保存完整原始镜像，写回时只改已经识别的字段，暂时没完全命名的机器设置会尽量原样保留。这一点很关键，因为对讲机不是普通数据库，很多未知位一旦被清空，表面看不出来，实际机器状态可能已经变了。</p>
        <p>蓝牙写频则更像在黑箱旁边一点点听回声。先要确认设备广播名和 FFE0/FFE1 特征值，再用 Web Bluetooth、CoreBluetooth 小脚本、APK 线索、官方 iOS 应用和手台读回内容逐块比对。期间最大的陷阱，是浏览器能成功写入特征值并不等于机器按预期解释了这段数据；曾经出现过写完以后机器里冒出一串 `404.00657`、`412.00757` 的怪频率。最后通过官方 Android APK 反编译和实机回读确认，8800Pro 蓝牙原生链路不是两个独立 `0x40` 块，而是 `52 addr 80` 读取、`57 addr 80 + 128 bytes` 写入。</p>
        <p>现在蓝牙读写频默认按官方 APK 的 `0x80` 原生块运行：网页内部仍以 64 字节保存，蓝牙读到 128 字节后拆成两个内部块，写回时再合成一个官方 128 字节包，并交给浏览器按实际 GATT 能力分片发送。实机测试说明不能只跳到某个变化信道单独写入，所以“常规写频”会按官方地址表全量顺序写完所有 `0x80` 包，优先保证机器内存边界稳定。蓝牙连接时页面还会额外显示“快速写频”按钮，继续使用之前摸出来的 `0x40` 双块流式写法，方便小范围改动时实机对照。</p>
        <p>所以这个网页看起来只是一个安静的控制台，底下其实是一套围绕 8800Pro 内存块反复试错出来的专用工具：从开源项目得到第一张草图，从 APK 和官方软件里找行为线索，再用真实手台一遍遍读、写、回读、对比，直到线写频和蓝牙写频都能被同一套编解码器解释清楚。能把这件事放进网页里运行，靠的是社区资料、浏览器硬件 API、持续备份和大量实机验证叠在一起。</p>

        <h4>更新日志</h4>
        <div className="changelog">
          <p><strong>全国中继台库</strong> 信道页接入 HamCQ 中继台数据，展开后懒加载 589 条记录，并支持按大区、省份、城市、名称、呼号、频率和亚音快速筛选。</p>
          <p><strong>中继台库重做</strong> 原来的小卡片改成全宽数据库面板，左侧列表、右侧写入预览，支持分批加载，选择后可直接写入当前信道。</p>
          <p><strong>连接入口重做</strong> 未连接时只显示全屏连接界面，先选择蓝牙或 USB，连接成功后再进入完整控制台。</p>
          <p><strong>断线自动恢复</strong> 设备重启或短暂断开时会自动尝试重连 3 次，失败后才提示回到未连接状态。</p>
          <p><strong>信道名称保留</strong> 写回信道时优先保留原机名称字节，避免未修改名称时被空值或不同填充方式覆盖。</p>
          <p><strong>全局交互动效</strong> 增加连接页、面板、列表、按钮和进度条的动效，并遵循系统减少动态设置。</p>
          <p><strong>官方 APK 链路同步</strong> 蓝牙常规写频切换为官方 Android APK 同款 `0x80` 原生块协议，并按地址表全量顺序写入，避免跳块写频。</p>
          <p><strong>蓝牙双写频入口</strong> 蓝牙连接时顶部显示“常规写频”和“快速写频”两个按钮；USB 写频线连接时只显示常规写频入口。</p>
          <p><strong>中继台布局修复</strong> 信道编辑区和中继台库改为上下独立布局，中继台展开后不再挤压信道编辑面板。</p>
          <p><strong>修复蓝牙写频帧污染</strong> 实机确认连续地址块必须使用 `header + data + data` 的流式写法；网页已停止给第二个连续块发送帧头，避免 `57 addr 40` 落入信道或 DTMF 数据。</p>
          <p><strong>官方链路对照</strong> 通过官方 iOS 应用的 RadioKit 框架和本地 CoreBluetooth 实机测试，确认 8800Pro 读写频主链路仍走 FFE1，FF31/FF32 不是普通读写块的替代通道。</p>
          <p><strong>回读保护</strong> 蓝牙写频完成后建议立即读频，页面会继续保留写频前自动备份，方便发现异常时回退。</p>
          <p><strong>实机校验通过</strong> 使用本地 CoreBluetooth 对真实 8800Pro 完成全量读、生成蓝牙写入计划、写回、逐块校验和再次全量读回，确认疑似污染信道为 0。</p>
          <p><strong>空信道清理</strong> 读到已被帧头污染的空信道时，会在页面中按空信道处理；再次通过 USB 写回时会编码为全 `FF` 空槽。</p>
          <p><strong>技术实现说明</strong> 关于页新增协议摸索过程，记录本项目如何结合开源项目、官方软件、APK 线索和实机读回逐步实现读写频。</p>
          <p><strong>实时连接监测</strong> 设备断开后会自动切换成未连接状态，并在页面里直接提示。</p>
          <p><strong>关于页整理</strong> 把项目说明、免责声明、致谢和更新日志放到同一个文字页面里，便于查看。</p>
          <p><strong>部署分流</strong> 服务器版本保留备案号，GitHub Pages 版本默认不显示备案号，避免不同发布场景混在一起。</p>
        </div>
      </div>
    </section>
  )
}

function DebugPanel({ logs, clear }: { logs: string[]; clear: () => void }) {
  return (
    <section className="panel">
      <div className="panel-heading">
        <div>
          <h3>通信日志</h3>
          <p>保留最近 300 行，方便定位握手、ACK、地址块和浏览器权限问题</p>
        </div>
        <button type="button" className="ghost-button" onClick={clear}>清空</button>
      </div>
      <pre className="debug-log">{logs.join('\n') || '暂无日志'}</pre>
    </section>
  )
}

interface AppDataDiffItem {
  path: string
  label: string
  before: unknown
  after: unknown
}

interface AppDataDiffGroup {
  label: string
  count: number
  items: AppDataDiffItem[]
}

interface AppDataDiffSummary {
  totalChanges: number
  groups: AppDataDiffGroup[]
}

interface DataPanelProps {
  data: AppData
  setData: (updater: (current: AppData) => AppData) => void
}

function TextField({
  label,
  value,
  onChange,
  onBlur,
  compact = false,
  hint,
  placeholder,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  onBlur?: () => void
  compact?: boolean
  hint?: string
  placeholder?: string
}) {
  return (
    <label className={`field ${compact ? 'compact' : ''}`}>
      <span>{label}</span>
      <input value={value} placeholder={placeholder} onChange={(event) => onChange(event.target.value)} onBlur={onBlur} />
      {hint ? <small>{hint}</small> : null}
    </label>
  )
}

function SelectField<T extends readonly string[]>({
  label,
  value,
  options,
  onChange,
  hint,
}: {
  label: string
  value: string
  options: T
  onChange: (value: T[number]) => void
  hint?: string
}) {
  return (
    <label className="field">
      <span>{label}</span>
      <select value={value} onChange={(event) => onChange(event.target.value as T[number])}>
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
      {hint ? <small>{hint}</small> : null}
    </label>
  )
}

function SelectIndex({
  label,
  value,
  options,
  onChange,
  compact = false,
  hint,
}: {
  label: string
  value: number
  options: readonly string[]
  onChange: (value: number) => void
  compact?: boolean
  hint?: string
}) {
  return (
    <label className={`field ${compact ? 'compact' : ''}`}>
      <span>{label}</span>
      <select value={value} onChange={(event: ChangeEvent<HTMLSelectElement>) => onChange(Number(event.target.value))}>
        {options.map((option, index) => (
          <option key={`${option}-${index}`} value={index}>
            {option}
          </option>
        ))}
      </select>
      {hint ? <small>{hint}</small> : null}
    </label>
  )
}

function cloneChannel(channel: Channel): Channel {
  return JSON.parse(JSON.stringify(channel)) as Channel
}

function getPreferredBankIndex(data: AppData) {
  const currentBank = data.functions.currentBankA
  if (data.channels[currentBank]?.some((channel) => channel.visible && channel.rxFreq)) return currentBank
  const firstFilledBank = data.channels.findIndex((bank) => bank.some((channel) => channel.visible && channel.rxFreq))
  return firstFilledBank >= 0 ? firstFilledBank : 0
}

const CHANNEL_DIFF_LABELS: Record<keyof Channel, string> = {
  id: '编号',
  rxFreq: '接收频率',
  rxTone: '接收亚音',
  txFreq: '发射频率',
  txTone: '发射亚音',
  txPower: '功率',
  bandwidth: '带宽',
  scanAdd: '扫描',
  busyLock: '忙锁',
  pttid: 'PTT-ID',
  signalGroup: '信令组',
  name: '名称',
  visible: '启用',
}

const VFO_DIFF_LABELS: Record<keyof AppData['vfos'], string> = {
  pttid: 'PTT-ID',
  vfoAFreq: 'A 频率',
  vfoBFreq: 'B 频率',
  vfoAOffset: 'A 差频',
  vfoBOffset: 'B 差频',
  vfoARxTone: 'A 接收亚音',
  vfoATxTone: 'A 发射亚音',
  vfoBRxTone: 'B 接收亚音',
  vfoBTxTone: 'B 发射亚音',
  vfoATxPower: 'A 功率',
  vfoBTxPower: 'B 功率',
  vfoABandwidth: 'A 带宽',
  vfoBBandwidth: 'B 带宽',
  vfoAStep: 'A 步进',
  vfoBStep: 'B 步进',
  vfoABusyLock: 'A 忙锁',
  vfoBBusyLock: 'B 忙锁',
  vfoASignalGroup: 'A 信令组',
  vfoBSignalGroup: 'B 信令组',
  vfoADirection: 'A 方向',
  vfoBDirection: 'B 方向',
  vfoAScramble: 'A 加扰',
  vfoBScramble: 'B 加扰',
}

function summarizeAppDataDiff(before: AppData, after: AppData): AppDataDiffSummary {
  const groups: AppDataDiffGroup[] = [
    diffPrimitiveGroup('区域名称', before.bankNames, after.bankNames, (index) => `区域 ${index + 1}`),
    diffChannelsGroup(before.channels, after.channels),
    diffObjectGroup('VFO', before.vfos, after.vfos, VFO_DIFF_LABELS),
    diffObjectGroup('功能设置', before.functions, after.functions, {}),
    diffObjectGroup('DTMF', before.dtmf, after.dtmf, {}),
    diffObjectGroup('FM 收音机', before.fm, after.fm, {}),
    diffBootImageGroup(before.bootImage, after.bootImage),
    diffRawBlocksGroup(before.rawBlocks, after.rawBlocks),
  ]
  return {
    groups,
    totalChanges: groups.reduce((total, group) => total + group.count, 0),
  }
}

function sanitizeRadioFrequencyDraft(value: string) {
  const cleaned = value.replace(/[^\d.]/g, '')
  const [integer = '', ...decimalParts] = cleaned.split('.')
  const decimal = decimalParts.join('').slice(0, 5)
  return `${integer.slice(0, 3)}${cleaned.includes('.') ? `.${decimal}` : ''}`
}

function sanitizeFmDraft(value: string) {
  const cleaned = value.replace(/[^\d.]/g, '')
  const [integer = '', ...decimalParts] = cleaned.split('.')
  const decimal = decimalParts.join('').slice(0, 1)
  return `${integer.slice(0, 3)}${cleaned.includes('.') ? `.${decimal}` : ''}`
}

function parseFmDraft(value: string) {
  if (!value || value.endsWith('.')) return undefined
  const parsed = Number(value)
  if (!Number.isFinite(parsed)) return undefined
  const scaled = Math.round(parsed * 10)
  return scaled >= 650 && scaled <= 1080 ? scaled : undefined
}

function formatFmDraft(value: number) {
  return value ? (value / 10).toFixed(1) : ''
}

function diffChannelsGroup(before: Channel[][] = [], after: Channel[][] = []): AppDataDiffGroup {
  const items: AppDataDiffItem[] = []
  const bankCount = Math.max(before.length, after.length)
  for (let bankIndex = 0; bankIndex < bankCount; bankIndex += 1) {
    const beforeBank = before[bankIndex] ?? []
    const afterBank = after[bankIndex] ?? []
    const channelCount = Math.max(beforeBank.length, afterBank.length)
    for (let channelIndex = 0; channelIndex < channelCount; channelIndex += 1) {
      const beforeChannel = beforeBank[channelIndex] ?? createEmptyChannel(channelIndex + 1)
      const afterChannel = afterBank[channelIndex] ?? createEmptyChannel(channelIndex + 1)
      for (const key of Object.keys(CHANNEL_DIFF_LABELS) as Array<keyof Channel>) {
        if (!sameValue(beforeChannel[key], afterChannel[key])) {
          items.push({
            path: `channels.${bankIndex}.${channelIndex}.${key}`,
            label: `区域 ${bankIndex + 1} / CH-${channelIndex + 1} / ${CHANNEL_DIFF_LABELS[key]}`,
            before: beforeChannel[key],
            after: afterChannel[key],
          })
        }
      }
    }
  }
  return { label: '信道', count: items.length, items }
}

function diffPrimitiveGroup<T>(label: string, before: T[] = [], after: T[] = [], itemLabel: (index: number) => string): AppDataDiffGroup {
  const items: AppDataDiffItem[] = []
  const length = Math.max(before.length, after.length)
  for (let index = 0; index < length; index += 1) {
    if (!sameValue(before[index], after[index])) {
      items.push({ path: `${label}.${index}`, label: itemLabel(index), before: before[index], after: after[index] })
    }
  }
  return { label, count: items.length, items }
}

function diffObjectGroup<T extends object>(label: string, before: T, after: T, labels: Partial<Record<keyof T, string>>): AppDataDiffGroup {
  const items: AppDataDiffItem[] = []
  const leftObject = before as Record<string, unknown>
  const rightObject = after as Record<string, unknown>
  const keys = new Set([...Object.keys(leftObject), ...Object.keys(rightObject)])
  keys.forEach((key) => {
    const typedKey = key as keyof T
    const left = leftObject[key]
    const right = rightObject[key]
    if (!sameValue(left, right)) {
      items.push({ path: `${label}.${key}`, label: labels[typedKey] ?? key, before: left, after: right })
    }
  })
  return { label, count: items.length, items }
}

function diffBootImageGroup(before?: AppData['bootImage'], after?: AppData['bootImage']): AppDataDiffGroup {
  const items: AppDataDiffItem[] = []
  const keys: Array<keyof NonNullable<AppData['bootImage']>> = ['name', 'width', 'height', 'dataUrl', 'rgb565']
  keys.forEach((key) => {
    const left = key === 'rgb565' ? before?.rgb565?.length : before?.[key]
    const right = key === 'rgb565' ? after?.rgb565?.length : after?.[key]
    if (!sameValue(left, right)) items.push({ path: `bootImage.${key}`, label: key === 'rgb565' ? 'RGB565 数据长度' : `开机图 ${key}`, before: left, after: right })
  })
  return { label: '开机图', count: items.length, items }
}

function diffRawBlocksGroup(before: AppData['rawBlocks'] = {}, after: AppData['rawBlocks'] = {}): AppDataDiffGroup {
  const items: AppDataDiffItem[] = []
  const keys = new Set([...Object.keys(before), ...Object.keys(after)])
  keys.forEach((key) => {
    if (!sameValue(before[key], after[key])) {
      items.push({ path: `rawBlocks.${key}`, label: `原始块 ${key}`, before: `${before[key]?.length ?? 0} bytes`, after: `${after[key]?.length ?? 0} bytes` })
    }
  })
  return { label: '原始镜像块', count: items.length, items }
}

function sameValue(left: unknown, right: unknown) {
  return JSON.stringify(left ?? null) === JSON.stringify(right ?? null)
}

function formatDiffValue(value: unknown) {
  if (value === undefined || value === null || value === '') return '空'
  if (typeof value === 'boolean') return value ? '是' : '否'
  if (Array.isArray(value)) return `${value.length} 项`
  const text = String(value)
  return text.length > 80 ? `${text.slice(0, 80)}...` : text
}

function statsLikeDate(value: string) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '未知时间'
  return date.toLocaleString(undefined, {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function wait(ms: number) {
  return new Promise((resolve) => window.setTimeout(resolve, ms))
}

export default App
