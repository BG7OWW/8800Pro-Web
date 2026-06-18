import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlus.setLogLevel(LogLevel.none);
  runApp(const Radio8800App());
}

class Radio8800App extends StatefulWidget {
  const Radio8800App({super.key});

  @override
  State<Radio8800App> createState() => _Radio8800AppState();
}

class _Radio8800AppState extends State<Radio8800App> {
  late final MobileStore store;

  @override
  void initState() {
    super.initState();
    store = MobileStore()..initialize();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '8800Pro Mobile',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0F9D8A),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFFF4FBF9),
            textTheme: Theme.of(
              context,
            ).textTheme.apply(fontFamily: 'PingFang SC'),
          ),
          home: HomeShell(store: store),
        );
      },
    );
  }
}

enum RootTab { overview, channels, settings, tools, guide, about }

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});

  final MobileStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  RootTab currentTab = RootTab.overview;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      OverviewPage(
        store: widget.store,
        onJump: (tab) => setState(() => currentTab = tab),
      ),
      ChannelsPage(store: widget.store),
      SettingsPage(store: widget.store),
      ToolsPage(store: widget.store),
      GuidePage(store: widget.store),
      const AboutPage(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(child: pages[currentTab.index]),
          if (widget.store.transferProgressValue != null)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: SafeArea(
                child: TransferProgressBanner(store: widget.store),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentTab.index,
        onDestinationSelected: (index) =>
            setState(() => currentTab = RootTab.values[index]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed_rounded), label: '总览'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: '信道'),
          NavigationDestination(
            icon: Icon(Icons.settings_suggest_rounded),
            label: '功能',
          ),
          NavigationDestination(icon: Icon(Icons.build_rounded), label: '工具'),
          NavigationDestination(
            icon: Icon(Icons.menu_book_rounded),
            label: '教程',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline_rounded),
            label: '关于',
          ),
        ],
      ),
    );
  }
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.store, required this.onJump});

  final MobileStore store;
  final ValueChanged<RootTab> onJump;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          pinned: true,
          backgroundColor: Colors.transparent,
          title: const Text('总览'),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.list(
            children: [
              if (store.notice != null) ...[
                NoticeBanner(message: store.notice!),
                const SizedBox(height: 16),
              ],
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '8800Pro Mobile',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Android 版和 iOS 版会保持同一套新手流程，把连接、读写、导入、备份和恢复集中到更顺手的路径里。',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        StatusPill(
                          label: store.linkState.label,
                          positive: store.linkState.isConnected,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    InfoStrip(title: '当前进度', detail: store.progressNote),
                    const SizedBox(height: 8),
                    InfoStrip(title: '最近操作', detail: store.lastOperation),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ActionButton(
                            label: '连接蓝牙',
                            icon: Icons.bluetooth_searching_rounded,
                            primary: true,
                            onPressed: store.connectBluetooth,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ActionButton(
                            label: '读频',
                            icon: Icons.download_rounded,
                            onPressed: store.readRadio,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ActionButton(
                            label: '写频',
                            icon: Icons.upload_rounded,
                            onPressed: store.writeRadio,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: MetricTile(
                            title: '正在操作的分组',
                            value: store.currentBankName,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MetricTile(
                            title: '已配信道',
                            value: '${store.data.visibleChannelCount}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MetricTile(
                            title: '本地备份',
                            value: '${store.backups.length}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ChannelManagementPanel(store: store),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: '推荐流程',
                      subtitle: '第一次建议先读频，再改一条信道试写，确认没问题后再批量整理。',
                    ),
                    const SizedBox(height: 12),
                    for (final step in DemoData.overviewSteps) ...[
                      HintTile(text: step),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: '快捷入口',
                      subtitle: '把最常用的几个入口直接放这里。',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: JumpTile(
                            title: '信道编辑',
                            icon: Icons.list_alt_rounded,
                            color: const Color(0xFF0F9D8A),
                            onTap: () => onJump(RootTab.channels),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: JumpTile(
                            title: '功能设置',
                            icon: Icons.tune_rounded,
                            color: const Color(0xFF326BFF),
                            onTap: () => onJump(RootTab.settings),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: JumpTile(
                            title: '工具箱',
                            icon: Icons.build_rounded,
                            color: const Color(0xFFFF8A00),
                            onTap: () => onJump(RootTab.tools),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: '当前分组里的信道',
                      subtitle: store.activeChannels.isEmpty
                          ? '这个分组还没有可用信道。'
                          : '先看一眼这组目前都写了什么。',
                    ),
                    const SizedBox(height: 12),
                    if (store.activeChannels.isEmpty)
                      const EmptyTile(
                        title: '还没有信道',
                        detail: '可以去信道页手动新建，也可以从中继台库或粘贴文本导入。',
                      )
                    else
                      for (final channel in store.activeChannels.take(4)) ...[
                        ChannelTile(channel: channel),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: '中继台速览',
                      subtitle: '内置一些常用中继台，后面可以继续扩展。',
                    ),
                    const SizedBox(height: 12),
                    for (final repeater in store.repeaters.take(4)) ...[
                      RepeaterTile(repeater: repeater),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ChannelsPage extends StatelessWidget {
  const ChannelsPage({super.key, required this.store});

  final MobileStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          pinned: true,
          backgroundColor: Colors.transparent,
          title: const Text('信道编辑'),
          actions: [
            IconButton(
              tooltip: '中继台库',
              icon: const Icon(Icons.cell_tower_rounded),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => RepeaterSheet(store: store),
              ),
            ),
            IconButton(
              tooltip: '粘贴导入',
              icon: const Icon(Icons.paste_rounded),
              onPressed: () async {
                await store.importFromClipboard();
                if (context.mounted) {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ImportSheet(store: store),
                  );
                }
              },
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.list(
            children: [
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: '选择分组与信道',
                      subtitle:
                          '当前分组：${store.currentBankName} · 显示 ${store.filteredChannels.length} / 64',
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<AppUIMode>(
                      segments: const [
                        ButtonSegment(
                          value: AppUIMode.basic,
                          label: Text('基础'),
                        ),
                        ButtonSegment(
                          value: AppUIMode.advanced,
                          label: Text('高级'),
                        ),
                      ],
                      selected: {store.uiMode},
                      onSelectionChanged: (value) =>
                          store.setUiMode(value.first),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (context, index) {
                          final selected = store.selectedBankIndex == index;
                          return ChoiceChip(
                            label: Text(store.data.bankNames[index]),
                            selected: selected,
                            onSelected: (_) => store.selectBank(index),
                          );
                        },
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemCount: store.data.bankNames.length,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: '搜索信道号、名称、频率',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: store.setChannelSearchText,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: store.showEmptyChannels,
                      title: const Text('显示空信道'),
                      onChanged: store.setShowEmptyChannels,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: store.showFieldHints,
                      title: const Text('显示填写提示'),
                      onChanged: store.setShowFieldHints,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: '信道列表', subtitle: '点一条再往下编辑。'),
                    const SizedBox(height: 12),
                    if (store.filteredChannels.isEmpty)
                      const EmptyTile(
                        title: '没有符合条件的信道',
                        detail: '可以切换分组、打开空信道，或者清空搜索关键词。',
                      )
                    else
                      for (final channel in store.filteredChannels) ...[
                        SelectableChannelTile(
                          channel: channel,
                          selected: channel.id == store.currentChannel.id,
                          onTap: () => store.selectChannel(channel.id),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(
                      title: 'CH-${store.currentChannel.id} 详情',
                      subtitle: store.currentChannel.visible
                          ? '这条信道会参与写回。'
                          : '当前还是空白信道，填完频率就会变成有效信道。',
                    ),
                    const SizedBox(height: 12),
                    if (store.showFieldHints) ...[
                      const HintTile(
                        text: '最常改的是接收频率、发射频率和发射亚音。很多中继台直接把这三项配对就够用。',
                      ),
                      const SizedBox(height: 12),
                    ],
                    FormFieldCard(
                      title: '信道名称',
                      child: TextFormField(
                        key: ValueKey(
                          'name-${store.currentChannel.id}-${store.currentChannel.name}',
                        ),
                        initialValue: store.currentChannel.name,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '例：梧桐山',
                        ),
                        onChanged: (value) => store.updateCurrentChannel(
                          (channel) => channel.name = value.characters
                              .take(12)
                              .toString(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FormFieldCard(
                      title: '接收频率',
                      child: TextFormField(
                        key: ValueKey(
                          'rx-${store.currentChannel.id}-${store.currentChannel.rxFreq}',
                        ),
                        initialValue: store.currentChannel.rxFreq,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '439.46250',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (value) => store.updateCurrentChannel(
                          (channel) => channel.rxFreq = value,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FormFieldCard(
                      title: '发射频率',
                      child: TextFormField(
                        key: ValueKey(
                          'tx-${store.currentChannel.id}-${store.currentChannel.txFreq}',
                        ),
                        initialValue: store.currentChannel.txFreq,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '434.46250',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (value) => store.updateCurrentChannel(
                          (channel) => channel.txFreq = value,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FormFieldCard(
                      title: '接收亚音',
                      child: DropdownButtonFormField<String>(
                        initialValue: store.currentChannel.rxTone,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: ToneLibrary.choices
                            .map(
                              (tone) => DropdownMenuItem(
                                value: tone,
                                child: Text(tone),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => store.updateCurrentChannel(
                          (channel) => channel.rxTone = value ?? 'OFF',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FormFieldCard(
                      title: '发射亚音',
                      child: DropdownButtonFormField<String>(
                        initialValue: store.currentChannel.txTone,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: ToneLibrary.choices
                            .map(
                              (tone) => DropdownMenuItem(
                                value: tone,
                                child: Text(tone),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => store.updateCurrentChannel(
                          (channel) => channel.txTone = value ?? 'OFF',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FormFieldCard(
                      title: '功率',
                      child: SegmentedButton<int>(
                        segments: List.generate(
                          RadioChoices.power.length,
                          (index) => ButtonSegment<int>(
                            value: index,
                            label: Text(RadioChoices.power[index]),
                          ),
                        ),
                        selected: {store.currentChannel.txPower},
                        onSelectionChanged: (value) =>
                            store.updateCurrentChannel(
                              (channel) => channel.txPower = value.first,
                            ),
                      ),
                    ),
                    if (store.uiMode == AppUIMode.advanced) ...[
                      const SizedBox(height: 10),
                      Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('更多参数'),
                          childrenPadding: const EdgeInsets.only(bottom: 4),
                          children: [
                            FormFieldCard(
                              title: '带宽',
                              child: DropdownButtonFormField<int>(
                                initialValue: store.currentChannel.bandwidth,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                ),
                                items: List.generate(
                                  RadioChoices.bandwidth.length,
                                  (index) => DropdownMenuItem(
                                    value: index,
                                    child: Text(RadioChoices.bandwidth[index]),
                                  ),
                                ),
                                onChanged: (value) =>
                                    store.updateCurrentChannel(
                                      (channel) =>
                                          channel.bandwidth = value ?? 0,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            FormFieldCard(
                              title: '扫描加入',
                              child: DropdownButtonFormField<int>(
                                initialValue: store.currentChannel.scanAdd,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                ),
                                items: List.generate(
                                  RadioChoices.onOff.length,
                                  (index) => DropdownMenuItem(
                                    value: index,
                                    child: Text(RadioChoices.onOff[index]),
                                  ),
                                ),
                                onChanged: (value) =>
                                    store.updateCurrentChannel(
                                      (channel) => channel.scanAdd = value ?? 0,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            FormFieldCard(
                              title: '忙锁',
                              child: DropdownButtonFormField<int>(
                                initialValue: store.currentChannel.busyLock,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                ),
                                items: List.generate(
                                  RadioChoices.onOff.length,
                                  (index) => DropdownMenuItem(
                                    value: index,
                                    child: Text(RadioChoices.onOff[index]),
                                  ),
                                ),
                                onChanged: (value) =>
                                    store.updateCurrentChannel(
                                      (channel) =>
                                          channel.busyLock = value ?? 0,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            FormFieldCard(
                              title: 'PTT ID',
                              child: DropdownButtonFormField<int>(
                                initialValue: store.currentChannel.pttId,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                ),
                                items: List.generate(
                                  RadioChoices.pttId.length,
                                  (index) => DropdownMenuItem(
                                    value: index,
                                    child: Text(RadioChoices.pttId[index]),
                                  ),
                                ),
                                onChanged: (value) =>
                                    store.updateCurrentChannel(
                                      (channel) => channel.pttId = value ?? 0,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ActionButton(
                            label: '写频',
                            icon: Icons.upload_rounded,
                            primary: true,
                            onPressed: store.writeRadio,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ActionButton(
                            label: '手动备份',
                            icon: Icons.save_rounded,
                            onPressed: () => store.createBackup('手动备份'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ActionButton(
                            label: '清空当前',
                            icon: Icons.delete_outline_rounded,
                            onPressed: store.clearCurrentChannel,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ActionButton(
                            label: '打开导入',
                            icon: Icons.playlist_add_rounded,
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => ImportSheet(store: store),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ChannelManagementPanel extends StatelessWidget {
  const ChannelManagementPanel({super.key, required this.store});

  final MobileStore store;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: '信道管理',
            subtitle: '可以新建、复制、剪切、粘贴、插入、删除并整理当前区域。',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: '新建',
                  icon: Icons.add_circle_outline_rounded,
                  primary: true,
                  onPressed: store.prepareNewChannelInCurrentBank,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ActionButton(
                  label: '整理区域',
                  icon: Icons.cleaning_services_rounded,
                  onPressed: store.compactCurrentBank,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: '复制',
                  icon: Icons.content_copy_rounded,
                  onPressed: store.copyCurrentChannel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ActionButton(
                  label: '剪切',
                  icon: Icons.content_cut_rounded,
                  onPressed: store.cutCurrentChannel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ActionButton(
                  label: '粘贴',
                  icon: Icons.content_paste_rounded,
                  onPressed: store.pasteToCurrentChannel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: '插入空信道',
                  icon: Icons.playlist_add_rounded,
                  onPressed: store.insertEmptyChannelAfterSelection,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ActionButton(
                  label: '删除上移',
                  icon: Icons.delete_sweep_rounded,
                  onPressed: store.deleteCurrentChannelAndShift,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});

  final MobileStore store;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool showHelp = false;

  MobileStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(
          pinned: true,
          backgroundColor: Colors.transparent,
          title: Text('功能设置'),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.list(
            children: [
              SettingsCard(
                title: '双段与显示',
                subtitle: '这组设置最容易影响“为什么机器里看不到刚写进去的信道”。',
                children: [
                  indexedField(
                    'A 分组',
                    store.data.functions.currentBankA,
                    store.data.bankNames,
                    (value) =>
                        store.updateFunction((f) => f.currentBankA = value),
                  ),
                  indexedField(
                    'B 分组',
                    store.data.functions.currentBankB,
                    store.data.bankNames,
                    (value) =>
                        store.updateFunction((f) => f.currentBankB = value),
                  ),
                  indexedField(
                    'A 工作模式',
                    store.data.functions.chAWorkmode,
                    RadioChoices.workMode,
                    (value) =>
                        store.updateFunction((f) => f.chAWorkmode = value),
                  ),
                  indexedField(
                    'B 工作模式',
                    store.data.functions.chBWorkmode,
                    RadioChoices.workMode,
                    (value) =>
                        store.updateFunction((f) => f.chBWorkmode = value),
                  ),
                  indexedField(
                    'A 显示',
                    store.data.functions.chADisplay,
                    RadioChoices.displayMode,
                    (value) =>
                        store.updateFunction((f) => f.chADisplay = value),
                  ),
                  indexedField(
                    'B 显示',
                    store.data.functions.chBDisplay,
                    RadioChoices.displayMode,
                    (value) =>
                        store.updateFunction((f) => f.chBDisplay = value),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SettingsCard(
                title: '整机行为',
                subtitle: '静噪、扫描、提示音、双守、自动锁这些都在这里。',
                children: [
                  indexedField(
                    '静噪等级',
                    store.data.functions.sql,
                    List.generate(10, (index) => '$index'),
                    (value) => store.updateFunction((f) => f.sql = value),
                  ),
                  indexedField(
                    '背光时间',
                    store.data.functions.backlight,
                    RadioChoices.backlight,
                    (value) => store.updateFunction((f) => f.backlight = value),
                  ),
                  indexedField(
                    '双守',
                    store.data.functions.dualStandby,
                    RadioChoices.onOff,
                    (value) =>
                        store.updateFunction((f) => f.dualStandby = value),
                  ),
                  indexedField(
                    '提示音',
                    store.data.functions.beep,
                    RadioChoices.onOff,
                    (value) => store.updateFunction((f) => f.beep = value),
                  ),
                  indexedField(
                    '语音提示',
                    store.data.functions.voice,
                    RadioChoices.onOff,
                    (value) => store.updateFunction((f) => f.voice = value),
                  ),
                  indexedField(
                    '自动锁',
                    store.data.functions.autoLock,
                    RadioChoices.autoLock,
                    (value) => store.updateFunction((f) => f.autoLock = value),
                  ),
                  indexedField(
                    '扫描模式',
                    store.data.functions.scanMode,
                    RadioChoices.scanMode,
                    (value) => store.updateFunction((f) => f.scanMode = value),
                  ),
                  indexedField(
                    '麦克风增益',
                    store.data.functions.micGain,
                    const ['低', '中', '高'],
                    (value) => store.updateFunction((f) => f.micGain = value),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: '开机与蓝牙',
                      subtitle: '把设备名、开机显示和蓝牙收音参数先整理好。',
                    ),
                    const SizedBox(height: 12),
                    indexedField(
                      '开机显示',
                      store.data.functions.powerOnDisplay,
                      const ['欢迎词', '电压', 'Logo'],
                      (value) =>
                          store.updateFunction((f) => f.powerOnDisplay = value),
                    ),
                    const SizedBox(height: 10),
                    indexedField(
                      '蓝牙音量',
                      store.data.functions.bluetoothAudioGain,
                      const ['低', '中', '高'],
                      (value) => store.updateFunction(
                        (f) => f.bluetoothAudioGain = value,
                      ),
                    ),
                    const SizedBox(height: 10),
                    indexedField(
                      '蓝牙麦克风',
                      store.data.functions.bluetoothMicGain,
                      const ['低', '中', '高'],
                      (value) => store.updateFunction(
                        (f) => f.bluetoothMicGain = value,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FormFieldCard(
                      title: '呼号 / 备注',
                      child: TextFormField(
                        key: ValueKey(
                          'callsign-${store.data.functions.callSign}',
                        ),
                        initialValue: store.data.functions.callSign,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '例：BG7OWW',
                        ),
                        onChanged: store.setCallSign,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: showHelp,
                      title: const Text('显示这些设置的解释'),
                      onChanged: (value) => setState(() => showHelp = value),
                    ),
                    if (showHelp) ...[
                      const SizedBox(height: 8),
                      for (final topic in DemoData.settingsHelp) ...[
                        InfoCard(title: topic.title, detail: topic.detail),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget indexedField(
    String title,
    int value,
    List<String> options,
    ValueChanged<int> onChanged,
  ) {
    return FormFieldCard(
      title: title,
      child: DropdownButtonFormField<int>(
        initialValue: min(value, options.length - 1),
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: List.generate(
          options.length,
          (index) =>
              DropdownMenuItem<int>(value: index, child: Text(options[index])),
        ),
        onChanged: (next) => onChanged(next ?? 0),
      ),
    );
  }
}

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.store});

  final MobileStore store;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  bool showDtmfHelp = false;
  bool showFmHelp = false;

  MobileStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(
          pinned: true,
          backgroundColor: Colors.transparent,
          title: Text('工具'),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.list(
            children: [
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: '蓝牙链路调试',
                      subtitle: '先把状态、通知和发包入口看清楚，后续接协议时会轻松很多。',
                    ),
                    const SizedBox(height: 12),
                    InfoStrip(title: '链路状态', detail: store.linkState.label),
                    const SizedBox(height: 8),
                    InfoStrip(title: '当前说明', detail: store.progressNote),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ActionButton(
                            label: '连接蓝牙',
                            icon: Icons.bluetooth_searching_rounded,
                            primary: true,
                            onPressed: store.connectBluetooth,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ActionButton(
                            label: '断开',
                            icon: Icons.link_off_rounded,
                            onPressed: store.disconnect,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ActionButton(
                            label: '发握手',
                            icon: Icons.send_rounded,
                            onPressed: store.sendHandshakeTest,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ActionButton(
                            label: '发 0x45',
                            icon: Icons.send_and_archive_rounded,
                            onPressed: store.sendEndFrameTest,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'VFO',
                      subtitle: '频率模式常用参数先在这里整理。',
                    ),
                    const SizedBox(height: 12),
                    VfoEditor(
                      title: 'A 段',
                      frequency: store.data.vfoA,
                      offset: store.data.vfoAOffset,
                      rxTone: store.data.vfoARxTone,
                      txTone: store.data.vfoATxTone,
                      onFrequencyChanged: (value) =>
                          store.updateVfo((data) => data.vfoA = value),
                      onOffsetChanged: (value) =>
                          store.updateVfo((data) => data.vfoAOffset = value),
                      onRxToneChanged: (value) =>
                          store.updateVfo((data) => data.vfoARxTone = value),
                      onTxToneChanged: (value) =>
                          store.updateVfo((data) => data.vfoATxTone = value),
                    ),
                    const SizedBox(height: 12),
                    VfoEditor(
                      title: 'B 段',
                      frequency: store.data.vfoB,
                      offset: store.data.vfoBOffset,
                      rxTone: store.data.vfoBRxTone,
                      txTone: store.data.vfoBTxTone,
                      onFrequencyChanged: (value) =>
                          store.updateVfo((data) => data.vfoB = value),
                      onOffsetChanged: (value) =>
                          store.updateVfo((data) => data.vfoBOffset = value),
                      onRxToneChanged: (value) =>
                          store.updateVfo((data) => data.vfoBRxTone = value),
                      onTxToneChanged: (value) =>
                          store.updateVfo((data) => data.vfoBTxTone = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'DTMF',
                      subtitle: '可以先填常用 ID 和组呼编码，后续接协议后会直接写回设备。',
                    ),
                    const SizedBox(height: 12),
                    FormFieldCard(
                      title: '本机 ID',
                      child: TextFormField(
                        key: ValueKey('dtmf-id-${store.data.dtmf.localId}'),
                        initialValue: store.data.dtmf.localId,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '100',
                        ),
                        onChanged: (value) =>
                            store.updateDtmf((dtmf) => dtmf.localId = value),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FormFieldCard(
                            title: '发码时长',
                            child: TextFormField(
                              key: ValueKey(
                                'dtmf-word-${store.data.dtmf.wordTime}',
                              ),
                              initialValue: '${store.data.dtmf.wordTime}',
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) => store.updateDtmf(
                                (dtmf) =>
                                    dtmf.wordTime = int.tryParse(value) ?? 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FormFieldCard(
                            title: '空闲间隔',
                            child: TextFormField(
                              key: ValueKey(
                                'dtmf-idle-${store.data.dtmf.idleTime}',
                              ),
                              initialValue: '${store.data.dtmf.idleTime}',
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) => store.updateDtmf(
                                (dtmf) =>
                                    dtmf.idleTime = int.tryParse(value) ?? 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: showDtmfHelp,
                      title: const Text('显示 DTMF 说明'),
                      onChanged: (value) =>
                          setState(() => showDtmfHelp = value),
                    ),
                    if (showDtmfHelp) ...[
                      for (final topic in DemoData.dtmfHelp) ...[
                        InfoCard(title: topic.title, detail: topic.detail),
                        const SizedBox(height: 10),
                      ],
                    ],
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: store.data.dtmf.groups.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 2.5,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemBuilder: (context, index) {
                        return FormFieldCard(
                          title: store.data.dtmf.groupNames[index],
                          compact: true,
                          child: TextFormField(
                            key: ValueKey(
                              'dtmf-$index-${store.data.dtmf.groups[index]}',
                            ),
                            initialValue: store.data.dtmf.groups[index],
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'DTMF',
                            ),
                            onChanged: (value) => store.updateDtmf(
                              (dtmf) => dtmf.groups[index] = value,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: 'FM 广播',
                      subtitle: '把常听的广播台写进记忆位。',
                    ),
                    const SizedBox(height: 12),
                    FormFieldCard(
                      title: '当前频点',
                      child: TextFormField(
                        key: ValueKey(
                          'fm-current-${store.data.fm.currentFreq}',
                        ),
                        initialValue: '${store.data.fm.currentFreq}',
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '904',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) => store.updateFm(
                          (fm) => fm.currentFreq = int.tryParse(value) ?? 904,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: showFmHelp,
                      title: const Text('显示 FM 说明'),
                      onChanged: (value) => setState(() => showFmHelp = value),
                    ),
                    if (showFmHelp) ...[
                      for (final topic in DemoData.fmHelp) ...[
                        InfoCard(title: topic.title, detail: topic.detail),
                        const SizedBox(height: 10),
                      ],
                    ],
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: store.data.fm.channels.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 1.8,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemBuilder: (context, index) {
                        final value = store.data.fm.channels[index];
                        return FormFieldCard(
                          title: '记忆 ${index + 1}',
                          compact: true,
                          child: TextFormField(
                            key: ValueKey('fm-$index-$value'),
                            initialValue: value == 0 ? '' : '$value',
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: '0',
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (text) => store.updateFm(
                              (fm) =>
                                  fm.channels[index] = int.tryParse(text) ?? 0,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: '开机图',
                      subtitle: '图片选择、RGB565 转换和专用写图协议正在开发中。',
                    ),
                    const SizedBox(height: 12),
                    const FormFieldCard(
                      title: '状态',
                      child: Row(
                        children: [
                          Icon(Icons.construction_rounded),
                          SizedBox(width: 10),
                          Expanded(child: Text('开发中，暂时不可写入开机图。')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    HintTile(text: store.data.bootImage.previewNote),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: '备份与恢复',
                      subtitle: '读频前和写频前都会自动留备份，这里也支持手动保存。',
                    ),
                    const SizedBox(height: 12),
                    if (store.backups.isEmpty)
                      const EmptyTile(
                        title: '还没有备份',
                        detail: '先点一次“手动备份”，就会在本机保留一个恢复点。',
                      )
                    else
                      for (final snapshot in store.backups.take(6)) ...[
                        BackupTile(
                          snapshot: snapshot,
                          onRestore: () => store.restoreBackup(snapshot.id),
                          onDelete: () => store.deleteBackup(snapshot.id),
                        ),
                        const SizedBox(height: 10),
                      ],
                    const SizedBox(height: 10),
                    ActionButton(
                      label: '手动备份',
                      icon: Icons.save_rounded,
                      onPressed: () => store.createBackup('手动备份'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: '通信日志',
                      subtitle: '保留最近 300 行，调链路问题时很有用。',
                    ),
                    const SizedBox(height: 12),
                    if (store.logs.isEmpty)
                      const EmptyTile(
                        title: '暂无日志',
                        detail: '建立一次蓝牙连接或发一次握手包，日志就会开始积累。',
                      )
                    else
                      for (final line in store.logs.take(18)) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            line,
                            style: const TextStyle(
                              fontFamily: 'Menlo',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    if (store.logs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ActionButton(
                        label: '清空日志',
                        icon: Icons.delete_outline_rounded,
                        onPressed: store.clearLogs,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class GuidePage extends StatelessWidget {
  const GuidePage({super.key, required this.store});

  final MobileStore store;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(
          pinned: true,
          backgroundColor: Colors.transparent,
          title: Text('教程'),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.list(
            children: [
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: '新手教程',
                      subtitle: '先把常见术语讲清楚，再进信道编辑会轻松很多。',
                    ),
                    const SizedBox(height: 12),
                    for (final item in DemoData.guideConcepts) ...[
                      InfoCard(title: item.$1, detail: item.$2),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: '网站功能映射',
                      subtitle: 'iOS / Android 两端会按这组结构对齐网页端。',
                    ),
                    const SizedBox(height: 12),
                    for (final item in DemoData.featureCards) ...[
                      InfoCard(title: item.$1, detail: item.$2),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(
                      title: '设置说明',
                      subtitle: '先看这些，会少走很多弯路。',
                    ),
                    const SizedBox(height: 12),
                    for (final item in DemoData.settingsHelp) ...[
                      InfoCard(title: item.title, detail: item.detail),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(
          pinned: true,
          backgroundColor: Colors.transparent,
          title: Text('关于'),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.list(
            children: [
              PanelCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '本项目由 BG7OWW 制作，旨在通过方便访问的网页与移动端，让各位 HAM 更方便地操作森海克斯 8800Pro 的各项功能，部分功能实现来自 GitHub 上的开源项目。',
                    ),
                    const SizedBox(height: 12),
                    const Text('如果有任何问题，请联系微信：samaaw1012'),
                    const SizedBox(height: 20),
                    const Text(
                      '免责声明',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '本软件仅供技术交流和个人学习使用。任何个人或组织在使用本软件时必须遵守中华人民共和国相关法律法规及无线电管理条例。',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '如因使用本软件造成任何损失，包括但不限于数据丢失或设备损坏，作者不承担任何法律责任。数据无价，提醒您注意备份。通过下载、安装或使用本软件，即表示您已阅读、理解并同意受项目免责声明约束。',
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '致谢',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('森海克斯官方写频软件'),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => launchGitHub(),
                      child: const Text(
                        'SydneyOwl/senhaix-freq-writer-enhanced',
                        style: TextStyle(
                          color: Color(0xFF326BFF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '更新日志',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final log in DemoData.updateLogs) ...[
                      Text(
                        '${log.version} · ${log.title}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        log.detail,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static void launchGitHub() {
    Clipboard.setData(
      const ClipboardData(
        text: 'https://github.com/SydneyOwl/senhaix-freq-writer-enhanced',
      ),
    );
  }
}

class RepeaterSheet extends StatefulWidget {
  const RepeaterSheet({super.key, required this.store});

  final MobileStore store;

  @override
  State<RepeaterSheet> createState() => _RepeaterSheetState();
}

class _RepeaterSheetState extends State<RepeaterSheet> {
  String selectedRegion = '';
  int? selectedProvinceCode;
  String keyword = '';

  MobileStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLibrary());
  }

  Future<void> _loadLibrary() async {
    await store.loadRepeaterLibraryIfNeeded();
    if (!mounted) return;
    setState(() {
      selectedRegion = selectedRegion.isNotEmpty
          ? selectedRegion
          : (store.repeaterRegions.isEmpty
                ? ''
                : store.repeaterRegions.first.label);
    });
  }

  List<RepeaterProvinceGroup> get selectedRegionProvinces {
    for (final region in store.repeaterRegions) {
      if (region.label == selectedRegion) {
        return region.children;
      }
    }
    return const [];
  }

  List<RepeaterEntry> get filteredRepeaters {
    final text = keyword.trim().toLowerCase();
    return store.repeaters.where((entry) {
      if (selectedRegion.isNotEmpty && entry.region != selectedRegion) {
        return false;
      }
      if (selectedProvinceCode != null &&
          entry.provinceCode != selectedProvinceCode) {
        return false;
      }
      if (text.isEmpty) {
        return true;
      }
      final haystack =
          '${entry.displayName} ${entry.locationText} ${entry.rxFreq} ${entry.txFreq} ${entry.toneText} ${entry.kind} ${entry.mode ?? ''}'
              .toLowerCase();
      return haystack.contains(text);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.94,
        builder: (context, controller) {
          final visibleRepeaters = filteredRepeaters;
          return Material(
            color: const Color(0xFFF4FBF9),
            child: ListView.builder(
              controller: controller,
              padding: const EdgeInsets.all(16),
              itemCount: visibleRepeaters.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return RepeaterFilterHeader(
                    status: store.repeaterLibraryStatus,
                    total: visibleRepeaters.length,
                    regions: store.repeaterRegions,
                    selectedRegion: selectedRegion,
                    provinces: selectedRegionProvinces,
                    selectedProvinceCode: selectedProvinceCode,
                    onRegionChanged: (value) {
                      setState(() {
                        selectedRegion = value;
                        selectedProvinceCode = null;
                      });
                    },
                    onProvinceChanged: (value) {
                      setState(() => selectedProvinceCode = value);
                    },
                    onKeywordChanged: (value) {
                      setState(() => keyword = value);
                    },
                  );
                }
                final repeater = visibleRepeaters[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () {
                      store.applyRepeater(repeater);
                      Navigator.of(context).pop();
                    },
                    child: RepeaterTile(repeater: repeater),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class RepeaterFilterHeader extends StatelessWidget {
  const RepeaterFilterHeader({
    super.key,
    required this.status,
    required this.total,
    required this.regions,
    required this.selectedRegion,
    required this.provinces,
    required this.selectedProvinceCode,
    required this.onRegionChanged,
    required this.onProvinceChanged,
    required this.onKeywordChanged,
  });

  final String status;
  final int total;
  final List<RepeaterRegionGroup> regions;
  final String selectedRegion;
  final List<RepeaterProvinceGroup> provinces;
  final int? selectedProvinceCode;
  final ValueChanged<String> onRegionChanged;
  final ValueChanged<int?> onProvinceChanged;
  final ValueChanged<String> onKeywordChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHeader(title: '中继台库', subtitle: '按大区和省份筛选，点一条写入当前信道。'),
        const SizedBox(height: 12),
        InfoStrip(title: '数据状态', detail: '$status · 当前显示 $total 条'),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: '搜索名称、城市、频率、亚音或制式',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: onKeywordChanged,
        ),
        const SizedBox(height: 12),
        if (regions.isNotEmpty) ...[
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final region = regions[index];
                return ChoiceChip(
                  label: Text(region.label),
                  selected: region.label == selectedRegion,
                  onSelected: (_) => onRegionChanged(region.label),
                );
              },
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemCount: regions.length,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (provinces.isNotEmpty) ...[
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ChoiceChip(
                    label: const Text('全部省份'),
                    selected: selectedProvinceCode == null,
                    onSelected: (_) => onProvinceChanged(null),
                  );
                }
                final province = provinces[index - 1];
                return ChoiceChip(
                  label: Text(
                    '${province.name} ${province.analogTotal + province.digiTotal}',
                  ),
                  selected: province.code == selectedProvinceCode,
                  onSelected: (_) => onProvinceChanged(province.code),
                );
              },
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemCount: provinces.length + 1,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class ImportSheet extends StatelessWidget {
  const ImportSheet({super.key, required this.store});

  final MobileStore store;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.6,
        maxChildSize: 0.97,
        builder: (context, controller) {
          return Material(
            color: const Color(0xFFF4FBF9),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                const SheetHeader(
                  title: '粘贴导入',
                  subtitle: '支持中继台描述、频率 + 频差 + 亚音这类文本。',
                ),
                const SizedBox(height: 12),
                PanelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(
                        title: '粘贴识别',
                        subtitle: '把文字粘进来后，点重新解析。',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller:
                            TextEditingController(text: store.importSourceText)
                              ..selection = TextSelection.collapsed(
                                offset: store.importSourceText.length,
                              ),
                        maxLines: 8,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        onChanged: store.setImportSourceText,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ActionButton(
                              label: '重新解析',
                              icon: Icons.find_in_page_rounded,
                              primary: true,
                              onPressed: store.parseImportSource,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ActionButton(
                              label: '全部插入',
                              icon: Icons.playlist_add_check_circle_rounded,
                              onPressed: store.applyAllImportedDrafts,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PanelCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(
                        title: '识别结果',
                        subtitle: '点单条可以覆盖当前信道，也可以批量插入。',
                      ),
                      const SizedBox(height: 12),
                      if (store.importedDrafts.isEmpty)
                        const EmptyTile(
                          title: '没有识别结果',
                          detail: '把中继台文字、频率或一整段说明粘贴进来后，点“重新解析”即可。',
                        )
                      else
                        for (final draft in store.importedDrafts) ...[
                          PanelCard(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  draft.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'RX ${draft.rxFreq} · TX ${draft.txFreq} · ${draft.tone}',
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                if (draft.notes.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    draft.notes,
                                    style: const TextStyle(
                                      color: Colors.black45,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ActionButton(
                                        label: '覆盖当前',
                                        icon: Icons.edit_rounded,
                                        onPressed: () =>
                                            store.applyImportedDraft(
                                              draft,
                                              appendAfterSelection: false,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ActionButton(
                                        label: '插到后面',
                                        icon: Icons.add_to_photos_rounded,
                                        onPressed: () =>
                                            store.applyImportedDraft(
                                              draft,
                                              appendAfterSelection: true,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class MobileStore extends ChangeNotifier {
  static const String bleService = '0000FFE0-0000-1000-8000-00805F9B34FB';
  static const String bleCharacteristic =
      '0000FFE1-0000-1000-8000-00805F9B34FB';
  static const String backupKey = 'radio8800_mobile.backups';
  static const int maxBackupCount = 20;

  RadioAppData data = RadioAppData.defaults();
  final List<RadioSnapshot> backups = [];
  final List<String> logs = [];
  final List<RepeaterEntry> repeaters = List.of(DemoData.repeaters);
  final List<RepeaterRegionGroup> repeaterRegions = [];
  final List<ImportedChannelDraft> importedDrafts = [];
  LinkState linkState = const LinkState.disconnected();
  NoticeMessage? notice;
  AppUIMode uiMode = AppUIMode.basic;
  int selectedBankIndex = 0;
  int selectedChannelIndex = 0;
  String importSourceText = '';
  String channelSearchText = '';
  bool showEmptyChannels = false;
  bool showFieldHints = true;
  String progressNote = '准备就绪';
  String lastOperation = '尚未开始读写';
  String repeaterLibraryStatus = '中继台库尚未加载';
  double? transferProgressValue;
  String transferProgressTitle = '';
  Channel? _copiedChannel;
  bool _hasLoadedRepeaterLibrary = false;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  final List<int> _rxBuffer = [];
  Completer<void>? _rxSignal;

  List<Channel> get currentBank => data.channels[selectedBankIndex];
  Channel get currentChannel => currentBank[selectedChannelIndex];
  List<Channel> get activeChannels => currentBank
      .where((channel) => channel.visible && channel.rxFreq.isNotEmpty)
      .toList();

  List<Channel> get filteredChannels {
    final keyword = channelSearchText.trim().toLowerCase();
    return currentBank.where((channel) {
      if (!showEmptyChannels && (!channel.visible || channel.rxFreq.isEmpty)) {
        return false;
      }
      if (keyword.isEmpty) {
        return true;
      }
      final search =
          '${channel.id} ${channel.name} ${channel.rxFreq} ${channel.txFreq}'
              .toLowerCase();
      return search.contains(keyword);
    }).toList();
  }

  String get currentBankName => data.bankNames[selectedBankIndex];

  Future<void> initialize() async {
    await _loadBackups();
    _log('应用已初始化');
    notifyListeners();
  }

  void setUiMode(AppUIMode mode) {
    uiMode = mode;
    notifyListeners();
  }

  void setChannelSearchText(String value) {
    channelSearchText = value;
    notifyListeners();
  }

  void setShowEmptyChannels(bool value) {
    showEmptyChannels = value;
    notifyListeners();
  }

  void setShowFieldHints(bool value) {
    showFieldHints = value;
    notifyListeners();
  }

  void selectBank(int index) {
    selectedBankIndex = index.clamp(0, data.bankNames.length - 1);
    selectedChannelIndex = 0;
    notifyListeners();
  }

  void selectChannel(int channelId) {
    selectedChannelIndex = channelId.clamp(1, currentBank.length).toInt() - 1;
    notifyListeners();
  }

  void updateCurrentChannel(void Function(Channel channel) change) {
    final channel = currentBank[selectedChannelIndex].copy();
    change(channel);
    channel.visible = channel.rxFreq.trim().isNotEmpty;
    data.channels[selectedBankIndex][selectedChannelIndex] = channel;
    data.updatedAt = DateTime.now();
    notifyListeners();
  }

  void clearCurrentChannel() {
    data.channels[selectedBankIndex][selectedChannelIndex] = Channel.empty(
      currentChannel.id,
    );
    data.updatedAt = DateTime.now();
    _success('已清空 CH-${currentChannel.id}');
  }

  void copyCurrentChannel() {
    _copiedChannel = currentChannel.copy();
    _success('已复制 CH-${currentChannel.id}');
  }

  void cutCurrentChannel() {
    _copiedChannel = currentChannel.copy();
    data.channels[selectedBankIndex][selectedChannelIndex] = Channel.empty(
      currentChannel.id,
    );
    data.updatedAt = DateTime.now();
    _success('已剪切 CH-${currentChannel.id}');
  }

  void pasteToCurrentChannel() {
    final copied = _copiedChannel;
    if (copied == null) {
      _warning('剪贴板里还没有信道');
      return;
    }
    data.channels[selectedBankIndex][selectedChannelIndex] = copied.copy()
      ..id = currentChannel.id;
    data.updatedAt = DateTime.now();
    _success('已粘贴到 CH-${currentChannel.id}');
  }

  void prepareNewChannelInCurrentBank() {
    final emptyIndex = currentBank.indexWhere(
      (channel) => !channel.visible || channel.rxFreq.trim().isEmpty,
    );
    if (emptyIndex < 0) {
      _warning('当前区域已满，请先清空一个信道或切换区域');
      return;
    }
    data.channels[selectedBankIndex][emptyIndex] = Channel.empty(
      emptyIndex + 1,
    );
    selectedChannelIndex = emptyIndex;
    channelSearchText = '';
    showEmptyChannels = true;
    data.updatedAt = DateTime.now();
    _success('已定位到 CH-${emptyIndex + 1}，填写接收频率后会参与写频');
  }

  void insertEmptyChannelAfterSelection() {
    var bank = List<Channel>.from(currentBank);
    final insertIndex = min(selectedChannelIndex + 1, bank.length - 1);
    bank.insert(insertIndex, Channel.empty(insertIndex + 1));
    bank = bank.take(64).toList();
    _renumber(bank);
    data.channels[selectedBankIndex] = bank;
    selectedChannelIndex = insertIndex;
    data.updatedAt = DateTime.now();
    _success('已插入空信道');
  }

  void deleteCurrentChannelAndShift() {
    final bank = List<Channel>.from(currentBank);
    if (!bank.asMap().containsKey(selectedChannelIndex)) {
      return;
    }
    bank.removeAt(selectedChannelIndex);
    bank.add(Channel.empty(64));
    _renumber(bank);
    data.channels[selectedBankIndex] = bank;
    selectedChannelIndex = min(selectedChannelIndex, bank.length - 1);
    data.updatedAt = DateTime.now();
    _success('已删除并上移后续信道');
  }

  void compactCurrentBank() {
    final active = currentBank
        .where((channel) => channel.visible && channel.rxFreq.trim().isNotEmpty)
        .map((channel) => channel.copy())
        .toList();
    final emptyCount = max(0, 64 - active.length);
    active.addAll(
      List.generate(emptyCount, (index) => Channel.empty(active.length + 1)),
    );
    _renumber(active);
    data.channels[selectedBankIndex] = active;
    selectedChannelIndex = min(selectedChannelIndex, active.length - 1);
    data.updatedAt = DateTime.now();
    _success('已整理当前区域，空信道移动到末尾');
  }

  void _renumber(List<Channel> channels) {
    for (var index = 0; index < channels.length; index += 1) {
      channels[index].id = index + 1;
      channels[index].visible = channels[index].rxFreq.trim().isNotEmpty;
    }
  }

  void updateFunction(void Function(RadioFunctionSettings settings) change) {
    change(data.functions);
    data.updatedAt = DateTime.now();
    notifyListeners();
  }

  void updateVfo(void Function(RadioAppData data) change) {
    change(data);
    data.updatedAt = DateTime.now();
    notifyListeners();
  }

  void updateDtmf(void Function(DtmfSettings data) change) {
    change(data.dtmf);
    data.updatedAt = DateTime.now();
    notifyListeners();
  }

  void updateFm(void Function(FmSettings data) change) {
    change(data.fm);
    data.updatedAt = DateTime.now();
    notifyListeners();
  }

  void updateBootImage(void Function(BootImageDraft image) change) {
    change(data.bootImage);
    data.updatedAt = DateTime.now();
    notifyListeners();
  }

  void setCallSign(String value) {
    data.functions.callSign = value.characters.take(12).toString();
    data.updatedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> connectBluetooth() async {
    progressNote = '正在准备蓝牙连接';
    linkState = const LinkState.scanning();
    notifyListeners();

    final permissionsReady = await _ensureBluetoothPermissions();
    if (!permissionsReady) {
      return;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      await _markBleUnavailable('蓝牙未开启，请先打开手机蓝牙');
      return;
    }

    try {
      _log('开始按 FFE0 服务扫描 8800Pro BLE 设备');
      var device = await _scanForRadio(
        filterByService: true,
        timeout: const Duration(seconds: 8),
      );
      if (device == null) {
        _log('按服务扫描超时，改用名称扫描');
        progressNote = '正在按名称扫描设备';
        notifyListeners();
        device = await _scanForRadio(
          filterByService: false,
          timeout: const Duration(seconds: 10),
        );
      }
      if (device == null) {
        await _markBleUnavailable('扫描超时，请确认对讲机蓝牙已开启并靠近手机');
        return;
      }
      await _connectToDevice(device);
    } catch (error) {
      await _markBleUnavailable('扫描失败：$error');
    }
  }

  Future<BluetoothDevice?> _scanForRadio({
    required bool filterByService,
    required Duration timeout,
  }) async {
    await _scanSub?.cancel();
    await FlutterBluePlus.stopScan();

    final completer = Completer<BluetoothDevice?>();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (_matchesRadio(result) && !completer.isCompleted) {
          completer.complete(result.device);
          break;
        }
      }
    });

    try {
      if (filterByService) {
        await FlutterBluePlus.startScan(
          timeout: timeout,
          withServices: [Guid(bleService)],
        );
      } else {
        await FlutterBluePlus.startScan(timeout: timeout);
      }
      return await completer.future.timeout(
        timeout + const Duration(seconds: 1),
        onTimeout: () => null,
      );
    } finally {
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _scanSub = null;
    }
  }

  bool _matchesRadio(ScanResult result) {
    final name = [
      result.device.platformName,
      result.advertisementData.advName,
      result.device.advName,
    ].join(' ').toLowerCase();
    return name.contains('walkie') ||
        name.contains('8800') ||
        name.contains('shx');
  }

  Future<bool> _ensureBluetoothPermissions() async {
    var androidSdk = 31;
    if (Platform.isAndroid) {
      androidSdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    }

    final requests = androidSdk >= 31
        ? <Permission>[Permission.bluetoothScan, Permission.bluetoothConnect]
        : <Permission>[Permission.locationWhenInUse];

    final statuses = await requests.request();
    final granted = statuses.values.every(_isPermissionGranted);

    if (granted) {
      return true;
    }

    final permanentlyDenied = statuses.values.any(
      (status) => status.isPermanentlyDenied,
    );
    if (permanentlyDenied) {
      await _markBleUnavailable(
        androidSdk >= 31
            ? '蓝牙权限被永久拒绝，请到系统设置里允许附近设备权限。'
            : '定位权限被永久拒绝，Android 11 及以下需要它才能扫描蓝牙设备。',
        disconnectDevice: false,
      );
      await openAppSettings();
      return false;
    }

    await _markBleUnavailable(
      androidSdk >= 31
          ? '需要附近设备/蓝牙权限才能扫描对讲机。'
          : 'Android 11 及以下需要定位权限才能扫描蓝牙设备。',
      disconnectDevice: false,
    );
    return false;
  }

  bool _isPermissionGranted(PermissionStatus status) =>
      status.isGranted || status.isLimited;

  Future<void> _connectToDevice(BluetoothDevice device) async {
    linkState = const LinkState.connecting();
    progressNote = '正在建立蓝牙连接';
    notifyListeners();
    _device = device;
    _log('发现设备 ${device.platformName}');

    await _connSub?.cancel();
    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        linkState = const LinkState.disconnected();
        progressNote = '连接已断开';
        notice = const NoticeMessage.warning('设备断开连接');
        _log('设备断开连接');
        notifyListeners();
      }
    });

    try {
      await device.connect(timeout: const Duration(seconds: 12), mtu: 247);
      linkState = const LinkState.discovering();
      progressNote = '正在发现服务与特征';
      notifyListeners();

      final services = await device.discoverServices();
      BluetoothCharacteristic? characteristic;
      for (final service in services) {
        if (_matchesUuid(service.uuid, bleService)) {
          for (final item in service.characteristics) {
            if (_matchesUuid(item.uuid, bleCharacteristic)) {
              characteristic = item;
              break;
            }
          }
        }
      }

      if (characteristic == null) {
        await _markBleUnavailable('未发现 FFE1 特征');
        return;
      }

      _characteristic = characteristic;
      await characteristic.setNotifyValue(true);
      await _notifySub?.cancel();
      _notifySub = characteristic.lastValueStream.listen((value) {
        if (value.isEmpty) {
          return;
        }
        _rxBuffer.addAll(value);
        _rxSignal?.complete();
        _rxSignal = null;
        _log('RX ${_hex(value)}');
      });

      linkState = const LinkState.connected('蓝牙已连接');
      progressNote = '蓝牙链路已连接';
      notice = const NoticeMessage.success('蓝牙链路已连接，可以先做握手测试或准备接协议。');
      _log('FFE1 通知已开启，蓝牙链路已就绪');
      notifyListeners();
    } catch (error) {
      await _markBleUnavailable('蓝牙连接失败：$error');
    }
  }

  Future<void> _markBleUnavailable(
    String message, {
    bool disconnectDevice = true,
  }) async {
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();
    await _notifySub?.cancel();
    _notifySub = null;
    if (disconnectDevice && _device != null) {
      await _connSub?.cancel();
      _connSub = null;
      try {
        await _device!.disconnect();
      } catch (_) {
        // Best effort cleanup; the user-facing state below is what matters.
      }
    }
    _characteristic = null;
    _device = null;
    _rxBuffer.clear();
    _rxSignal = null;
    linkState = const LinkState.disconnected();
    progressNote = '未连接';
    _warning(message);
  }

  bool _matchesUuid(Guid uuid, String expected) {
    final current = _canonicalUuid(uuid.toString());
    final target = _canonicalUuid(expected);
    if (current == target) return true;
    if (current.length == 4 && target.startsWith('0000$current')) return true;
    if (target.length == 4 && current.startsWith('0000$target')) return true;
    return current.endsWith(target) || target.endsWith(current);
  }

  String _canonicalUuid(String value) => value
      .toLowerCase()
      .replaceAll('-', '')
      .replaceFirst(
        RegExp(r'^0000([0-9a-f]{4})00001000800000805f9b34fb$'),
        r'$1',
      );

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await _connSub?.cancel();
    await _scanSub?.cancel();
    if (_device != null) {
      await _device!.disconnect();
    }
    _characteristic = null;
    _device = null;
    _rxBuffer.clear();
    _rxSignal = null;
    linkState = const LinkState.disconnected();
    progressNote = '连接已断开';
    notice = const NoticeMessage.neutral('设备已断开。');
    _log('蓝牙连接已断开');
    notifyListeners();
  }

  void readRadio() {
    unawaited(_readRadio());
  }

  void writeRadio() {
    unawaited(_writeRadio());
  }

  Future<void> sendHandshakeTest() async {
    await _sendAscii('PROGRAMSHXPU');
    _log('手动发送握手字串 PROGRAMSHXPU');
  }

  Future<void> sendEndFrameTest() async {
    await _sendBytes(Uint8List.fromList(const [0x45]));
    _log('手动发送结束字节 45');
  }

  bool createBackup(String title, {bool automatic = false}) {
    if (!data.hasBackupContent) {
      if (!automatic) {
        _warning('当前没有有效信道或设备原始数据，已跳过备份。');
      } else {
        _log('跳过自动备份：当前没有有效内容');
      }
      return false;
    }
    if (backups.isNotEmpty &&
        backups.first.data.backupSignature == data.backupSignature) {
      if (!automatic) {
        _warning('当前内容与最近备份一致，已跳过重复备份。');
      } else {
        _log('跳过自动备份：内容与最近备份一致');
      }
      return false;
    }
    backups.insert(
      0,
      RadioSnapshot(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        createdAt: DateTime.now(),
        data: data.copy(),
      ),
    );
    if (backups.length > maxBackupCount) {
      backups.removeRange(maxBackupCount, backups.length);
    }
    _persistBackups();
    if (!automatic) {
      notice = NoticeMessage.success('已创建备份：$title');
      _log('已创建备份：$title');
    }
    notifyListeners();
    return true;
  }

  void restoreBackup(String id) {
    final snapshot = backups.firstWhere((item) => item.id == id);
    data = snapshot.data.copy();
    selectedBankIndex = min(selectedBankIndex, data.bankNames.length - 1);
    selectedChannelIndex = min(
      selectedChannelIndex,
      data.channels[selectedBankIndex].length - 1,
    );
    _success('已恢复备份：${snapshot.title}');
  }

  void deleteBackup(String id) {
    final index = backups.indexWhere((item) => item.id == id);
    if (index < 0) {
      _warning('没有找到这份备份');
      return;
    }
    final title = backups[index].title;
    backups.removeAt(index);
    unawaited(_persistBackups());
    _success('已删除备份：$title');
  }

  void clearLogs() {
    logs
      ..clear()
      ..add('${DateFormat('HH:mm:ss').format(DateTime.now())}  日志已清空');
    notice = const NoticeMessage.success('日志已清空');
    notifyListeners();
  }

  void applyRepeater(RepeaterEntry entry) {
    updateCurrentChannel((channel) {
      channel.name = entry.displayName.characters.take(12).toString();
      channel.rxFreq = entry.rxFreq;
      channel.txFreq = entry.txFreq.trim().isEmpty
          ? _offsetFrequency(entry.rxFreq, entry.offset)
          : entry.txFreq;
      final explicitRxTone = _normalizeTone(entry.rxTone);
      final explicitTxTone = _normalizeTone(entry.txTone);
      final fallbackTone = _normalizeTone(entry.toneText);
      final usesTsq = entry.toneText.toUpperCase().contains('TSQ');
      channel.rxTone = explicitRxTone != 'OFF'
          ? explicitRxTone
          : (usesTsq ? fallbackTone : 'OFF');
      channel.txTone = explicitTxTone != 'OFF' ? explicitTxTone : fallbackTone;
      channel.txPower = 0;
      channel.bandwidth = 0;
      channel.scanAdd = 1;
      channel.busyLock = 1;
    });
    _success(
      '已将 ${entry.displayName} 写入 $currentBankName / CH-${currentChannel.id}',
    );
  }

  Future<void> loadRepeaterLibraryIfNeeded() async {
    if (_hasLoadedRepeaterLibrary) {
      return;
    }
    _hasLoadedRepeaterLibrary = true;
    repeaterLibraryStatus = '正在加载 HamCQ 中继台库...';
    notifyListeners();
    try {
      final package = await RepeaterLibraryLoader.loadPackagedLibrary();
      repeaters
        ..clear()
        ..addAll(package.repeaters);
      repeaterRegions
        ..clear()
        ..addAll(package.regions);
      repeaterLibraryStatus =
          'HamCQ ${package.total} 条，更新于 ${package.fetchedAt.substring(0, min(10, package.fetchedAt.length))}';
      _log('已加载 HamCQ 中继台库 ${package.total} 条');
    } catch (error) {
      repeaters
        ..clear()
        ..addAll(DemoData.repeaters);
      repeaterRegions.clear();
      repeaterLibraryStatus = '中继台库加载失败，已使用演示数据';
      _warning('中继台库加载失败：$error');
    }
    notifyListeners();
  }

  Future<void> importFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    importSourceText = data?.text ?? '';
    parseImportSource();
  }

  void setImportSourceText(String value) {
    importSourceText = value;
  }

  void parseImportSource() {
    importedDrafts
      ..clear()
      ..addAll(ImportParser.parse(importSourceText));
    if (importedDrafts.isEmpty) {
      _warning('没有识别到可导入的中继台或频率信息');
    } else {
      _success('识别到 ${importedDrafts.length} 条可导入记录');
    }
  }

  void applyImportedDraft(
    ImportedChannelDraft draft, {
    required bool appendAfterSelection,
  }) {
    if (appendAfterSelection) {
      _insertDrafts([draft], selectedChannelIndex);
    } else {
      data.channels[selectedBankIndex][selectedChannelIndex] = draft
          .makeChannel(currentChannel.id);
      notifyListeners();
    }
    _success('已导入 ${draft.title}');
  }

  void applyAllImportedDrafts() {
    if (importedDrafts.isEmpty) {
      return;
    }
    _insertDrafts(importedDrafts, selectedChannelIndex);
    _success('已批量导入 ${importedDrafts.length} 条记录');
  }

  void _insertDrafts(List<ImportedChannelDraft> drafts, int index) {
    var insertion = index;
    for (final draft in drafts) {
      if (insertion >= currentBank.length) {
        break;
      }
      data.channels[selectedBankIndex][insertion] = draft.makeChannel(
        insertion + 1,
      );
      insertion += 1;
    }
    data.updatedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> _sendAscii(String value) async {
    await _sendBytes(Uint8List.fromList(ascii.encode(value)));
  }

  Future<void> _readRadio() async {
    if (!_ensureBleReady()) {
      return;
    }
    if (_isTransferActive()) {
      return;
    }
    createBackup('读频前自动备份', automatic: true);
    lastOperation = '读频';
    progressNote = '正在握手';
    _setTransferProgress('读频：正在握手', 0);

    try {
      await _performHandshake();
      final next = RadioAppData.defaults();
      final addresses = ShxCodec.readWriteAddresses();
      for (var index = 0; index < addresses.length; index += 1) {
        final address = addresses[index];
        progressNote =
            '读取 ${ShxCodec.addressLabel(address)} ${index + 1}/${addresses.length}';
        _setTransferProgress(progressNote, index / addresses.length);
        final frame = await _readBlock(address);
        ShxCodec.applyBlock(next, address, frame);
        _setTransferProgress(progressNote, (index + 1) / addresses.length);
        await Future<void>.delayed(const Duration(milliseconds: 45));
      }
      await _writePacket(Uint8List.fromList(const [0x45]));
      next.updatedAt = DateTime.now();
      data = next;
      selectedBankIndex = min(selectedBankIndex, data.bankNames.length - 1);
      selectedChannelIndex = min(
        selectedChannelIndex,
        data.channels[selectedBankIndex].length - 1,
      );
      progressNote = '读频完成';
      lastOperation = '读频完成';
      _success('读频完成，已读取 ${data.visibleChannelCount} 个有效信道');
      await _completeTransferProgress('读频完成');
    } catch (error) {
      progressNote = '读频失败';
      _clearTransferProgress();
      _warning('读频失败：$error');
    }
  }

  Future<void> _writeRadio() async {
    if (!_ensureBleReady()) {
      return;
    }
    if (_isTransferActive()) {
      return;
    }
    if (data.visibleChannelCount == 0) {
      _warning('当前没有有效信道，已取消写频。');
      return;
    }
    createBackup('写频前自动备份', automatic: true);
    lastOperation = '写频';
    progressNote = '正在握手';
    _setTransferProgress('写频：正在握手', 0);

    try {
      await _performHandshake();
      final blocks = ShxCodec.bluetoothWriteBlocks(data);
      final pairs = ShxCodec.groupBluetoothWritePairs(blocks);
      final total = pairs.length * 2;
      for (var index = 0; index < pairs.length; index += 1) {
        final first = pairs[index].$1;
        final second = pairs[index].$2;
        progressNote =
            '写入 ${ShxCodec.addressLabel(first.address)} ${index * 2 + 1}/$total';
        _setTransferProgress(progressNote, index / pairs.length);
        await _writeBluetoothPair(first, second);
        await _readAck(
          '蓝牙写入失败：${ShxCodec.addressLabel(first.address)} / ${ShxCodec.addressLabel(second.address)}',
          const Duration(seconds: 6),
        );
        _setTransferProgress(progressNote, (index + 1) / pairs.length);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      await _writePacket(Uint8List.fromList(const [0x45]));
      data.updatedAt = DateTime.now();
      progressNote = '写频完成';
      lastOperation = '写频完成';
      _success('写频完成，共写入 $total 个数据块');
      await _completeTransferProgress('写频完成');
    } catch (error) {
      progressNote = '写频失败';
      _clearTransferProgress();
      _warning('写频失败：$error');
    }
  }

  bool _isTransferActive() {
    if (transferProgressValue == null) {
      return false;
    }
    _warning('当前正在传输，请等待本次读写完成。');
    return true;
  }

  void _setTransferProgress(String title, double value) {
    transferProgressTitle = title;
    transferProgressValue = value.clamp(0, 1).toDouble();
    notifyListeners();
  }

  Future<void> _completeTransferProgress(String title) async {
    _setTransferProgress(title, 1);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _clearTransferProgress();
  }

  void _clearTransferProgress() {
    transferProgressValue = null;
    transferProgressTitle = '';
    notifyListeners();
  }

  bool _ensureBleReady() {
    if (_characteristic == null || !linkState.isConnected) {
      _warning('请先连接蓝牙设备');
      return false;
    }
    return true;
  }

  Future<void> _performHandshake() async {
    _drainRx();
    await _writePacket(Uint8List.fromList(ascii.encode('PROGRAMSHXPU')));
    _log('TX PROGRAMSHXPU');
    await _readAck('握手失败：未收到 ACK', const Duration(seconds: 5));
    await _writePacket(Uint8List.fromList(const [0x46]));
    _log('TX 46');
    final ident = await _readIdent();
    _log('RX IDENT ${_hex(ident)}');
  }

  Future<Uint8List> _readBlock(int address) async {
    final request = ShxCodec.readFrame(address);
    await _writePacket(request);
    _log('TX READ ${ShxCodec.addressLabel(address)} ${_hex(request)}');
    final frame = await _readFrame(address);
    _log(
      'RX ${ShxCodec.addressLabel(address)} ${_hex(frame.take(8).toList())} ...',
    );
    return frame;
  }

  Future<Uint8List> _readFrame(int address) async {
    final expectedHigh = (address >> 8) & 0xff;
    final expectedLow = address & 0xff;
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    final window = <int>[];
    while (DateTime.now().isBefore(deadline)) {
      final byte = await _readExact(
        1,
        deadline.difference(DateTime.now()),
      ).catchError((_) => Uint8List(0));
      if (byte.isEmpty) {
        continue;
      }
      window.add(byte[0]);
      if (window.length > 4) {
        window.removeAt(0);
      }
      if (window.length == 4 &&
          window[0] == 0x52 &&
          window[1] == expectedHigh &&
          window[2] == expectedLow &&
          window[3] == 0x40) {
        final payload = await _readExact(
          64,
          deadline.difference(DateTime.now()),
        );
        final frame = Uint8List(68);
        frame.setRange(0, 4, window);
        frame.setRange(4, 68, payload);
        return frame;
      }
    }
    throw '读取 ${ShxCodec.addressLabel(address)} 数据不完整';
  }

  Future<void> _writeBluetoothPair(ShxBlock first, ShxBlock second) async {
    if (second.address == first.address + 0x40) {
      final header = Uint8List.fromList([
        0x57,
        (first.address >> 8) & 0xff,
        first.address & 0xff,
        0x40,
      ]);
      await _writePacket(header);
      _log(
        'TX BLE HEADER ${ShxCodec.addressLabel(first.address)} ${_hex(header)}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _writePacket(first.payload);
      _log(
        'TX BLE DATA ${ShxCodec.addressLabel(first.address)} ${_hex(first.payload.take(8).toList())} ...',
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await _writePacket(second.payload);
      _log(
        'TX BLE DATA ${ShxCodec.addressLabel(second.address)} ${_hex(second.payload.take(8).toList())} ...',
      );
      return;
    }

    await _writePacket(ShxCodec.writeFrame(first.address, first.payload));
    _log(
      'TX BLE WRITE ${ShxCodec.addressLabel(first.address)} ${_hex(first.payload.take(8).toList())} ...',
    );
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await _writePacket(ShxCodec.writeFrame(second.address, second.payload));
    _log(
      'TX BLE WRITE ${ShxCodec.addressLabel(second.address)} ${_hex(second.payload.take(8).toList())} ...',
    );
  }

  Future<void> _readAck(String message, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final byte = await _readExact(
        1,
        deadline.difference(DateTime.now()),
      ).catchError((_) => Uint8List(0));
      if (byte.isEmpty) {
        continue;
      }
      if (byte[0] == 0x06) {
        return;
      }
    }
    throw message;
  }

  Future<Uint8List> _readIdent() async {
    final bytes = <int>[];
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final byte = await _readExact(
        1,
        deadline.difference(DateTime.now()),
      ).catchError((_) => Uint8List(0));
      if (byte.isEmpty) {
        continue;
      }
      bytes.add(byte[0]);
      final start = bytes.indexOf(0x01);
      if (start >= 0 && bytes.length - start >= 16) {
        return Uint8List.fromList(bytes.sublist(start, start + 16));
      }
    }
    throw '握手失败：未收到设备标识';
  }

  Future<void> _sendBytes(Uint8List bytes) async {
    if (bytes.length > 20) {
      for (var offset = 0; offset < bytes.length; offset += 20) {
        final end = min(offset + 20, bytes.length);
        final chunk = bytes.sublist(offset, end);
        await _writePacket(chunk);
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      return;
    }
    await _writePacket(bytes);
  }

  Future<void> _writePacket(Uint8List bytes) async {
    final characteristic = _characteristic;
    if (characteristic == null) {
      _warning('蓝牙链路未就绪，暂时无法发包');
      return;
    }
    await characteristic.write(bytes, withoutResponse: false);
    _log('TX ${_hex(bytes)}');
  }

  Future<Uint8List> _readExact(int length, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_rxBuffer.length < length) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException('读取超时');
      }
      _rxSignal ??= Completer<void>();
      await _rxSignal!.future.timeout(remaining);
    }
    final out = Uint8List.fromList(_rxBuffer.take(length).toList());
    _rxBuffer.removeRange(0, length);
    return out;
  }

  void _drainRx() {
    _rxBuffer.clear();
    _rxSignal = null;
  }

  Future<void> _loadBackups() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(backupKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    backups
      ..clear()
      ..addAll(
        decoded.map(
          (item) => RadioSnapshot.fromJson(item as Map<String, dynamic>),
        ),
      );
    if (backups.length > maxBackupCount) {
      backups.removeRange(maxBackupCount, backups.length);
      await _persistBackups();
    }
  }

  Future<void> _persistBackups() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = jsonEncode(backups.map((item) => item.toJson()).toList());
    await preferences.setString(backupKey, raw);
  }

  void _success(String text) {
    notice = NoticeMessage.success(text);
    _log(text);
    notifyListeners();
  }

  void _warning(String text) {
    notice = NoticeMessage.warning(text);
    _log(text);
    notifyListeners();
  }

  void _log(String message) {
    final stamp = DateFormat('HH:mm:ss').format(DateTime.now());
    logs.insert(0, '$stamp  $message');
    if (logs.length > 300) {
      logs.removeRange(300, logs.length);
    }
  }

  String _normalizeTone(String? source) {
    if (source == null || source.trim().isEmpty) {
      return 'OFF';
    }
    final cleaned = source
        .replaceFirst(RegExp('^TSQ', caseSensitive: false), '')
        .replaceFirst(RegExp('^T', caseSensitive: false), '')
        .trim();
    if (cleaned == 'OFF' || cleaned == '0' || cleaned == '无') {
      return 'OFF';
    }
    final numeric = double.tryParse(cleaned);
    if (numeric == null) {
      return 'OFF';
    }
    return numeric % 1 == 0 ? numeric.toStringAsFixed(1) : '$numeric';
  }

  String _offsetFrequency(String rx, String offset) {
    final rxValue = double.tryParse(rx);
    final offsetValue = double.tryParse(offset);
    if (rxValue == null || offsetValue == null) {
      return rx;
    }
    return (rxValue + offsetValue).toStringAsFixed(5);
  }

  String _hex(List<int> bytes) => bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');

  @override
  void dispose() {
    _notifySub?.cancel();
    _connSub?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }
}

enum AppUIMode { basic, advanced }

class LinkState {
  const LinkState._(this.label, this.isConnected);

  const LinkState.disconnected() : this._('未连接', false);
  const LinkState.scanning() : this._('正在搜索设备', false);
  const LinkState.connecting() : this._('正在连接', false);
  const LinkState.discovering() : this._('正在初始化链路', false);
  const LinkState.connected(String label) : this._(label, true);

  final String label;
  final bool isConnected;
}

class NoticeMessage {
  const NoticeMessage.neutral(this.text) : tone = NoticeTone.neutral;
  const NoticeMessage.success(this.text) : tone = NoticeTone.success;
  const NoticeMessage.warning(this.text) : tone = NoticeTone.warning;

  final String text;
  final NoticeTone tone;
}

enum NoticeTone { neutral, success, warning }

class Channel {
  Channel({
    required this.id,
    this.rxFreq = '',
    this.rxTone = 'OFF',
    this.txFreq = '',
    this.txTone = 'OFF',
    this.txPower = 0,
    this.bandwidth = 0,
    this.scanAdd = 0,
    this.busyLock = 0,
    this.pttId = 0,
    this.signalGroup = 0,
    this.name = '',
    this.visible = false,
  });

  int id;
  String rxFreq;
  String rxTone;
  String txFreq;
  String txTone;
  int txPower;
  int bandwidth;
  int scanAdd;
  int busyLock;
  int pttId;
  int signalGroup;
  String name;
  bool visible;

  factory Channel.empty(int id) => Channel(id: id);

  Channel copy() => Channel.fromJson(toJson());

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    id: json['id'] as int,
    rxFreq: json['rxFreq'] as String? ?? '',
    rxTone: json['rxTone'] as String? ?? 'OFF',
    txFreq: json['txFreq'] as String? ?? '',
    txTone: json['txTone'] as String? ?? 'OFF',
    txPower: json['txPower'] as int? ?? 0,
    bandwidth: json['bandwidth'] as int? ?? 0,
    scanAdd: json['scanAdd'] as int? ?? 0,
    busyLock: json['busyLock'] as int? ?? 0,
    pttId: json['pttId'] as int? ?? 0,
    signalGroup: json['signalGroup'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    visible: json['visible'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'rxFreq': rxFreq,
    'rxTone': rxTone,
    'txFreq': txFreq,
    'txTone': txTone,
    'txPower': txPower,
    'bandwidth': bandwidth,
    'scanAdd': scanAdd,
    'busyLock': busyLock,
    'pttId': pttId,
    'signalGroup': signalGroup,
    'name': name,
    'visible': visible,
  };
}

class RadioFunctionSettings {
  RadioFunctionSettings();

  int sql = 3;
  int backlight = 3;
  int dualStandby = 0;
  int beep = 1;
  int voice = 1;
  int scanMode = 1;
  int chADisplay = 0;
  int chBDisplay = 0;
  int autoLock = 1;
  int chAWorkmode = 0;
  int chBWorkmode = 0;
  int powerOnDisplay = 2;
  int micGain = 1;
  int currentBankA = 1;
  int currentBankB = 1;
  int bluetoothAudioGain = 1;
  int bluetoothMicGain = 1;
  String callSign = '';

  RadioFunctionSettings copy() => RadioFunctionSettings.fromJson(toJson());

  factory RadioFunctionSettings.fromJson(Map<String, dynamic> json) {
    final settings = RadioFunctionSettings();
    settings.sql = json['sql'] as int? ?? settings.sql;
    settings.backlight = json['backlight'] as int? ?? settings.backlight;
    settings.dualStandby = json['dualStandby'] as int? ?? settings.dualStandby;
    settings.beep = json['beep'] as int? ?? settings.beep;
    settings.voice = json['voice'] as int? ?? settings.voice;
    settings.scanMode = json['scanMode'] as int? ?? settings.scanMode;
    settings.chADisplay = json['chADisplay'] as int? ?? settings.chADisplay;
    settings.chBDisplay = json['chBDisplay'] as int? ?? settings.chBDisplay;
    settings.autoLock = json['autoLock'] as int? ?? settings.autoLock;
    settings.chAWorkmode = json['chAWorkmode'] as int? ?? settings.chAWorkmode;
    settings.chBWorkmode = json['chBWorkmode'] as int? ?? settings.chBWorkmode;
    settings.powerOnDisplay =
        json['powerOnDisplay'] as int? ?? settings.powerOnDisplay;
    settings.micGain = json['micGain'] as int? ?? settings.micGain;
    settings.currentBankA =
        json['currentBankA'] as int? ?? settings.currentBankA;
    settings.currentBankB =
        json['currentBankB'] as int? ?? settings.currentBankB;
    settings.bluetoothAudioGain =
        json['bluetoothAudioGain'] as int? ?? settings.bluetoothAudioGain;
    settings.bluetoothMicGain =
        json['bluetoothMicGain'] as int? ?? settings.bluetoothMicGain;
    settings.callSign = json['callSign'] as String? ?? '';
    return settings;
  }

  Map<String, dynamic> toJson() => {
    'sql': sql,
    'backlight': backlight,
    'dualStandby': dualStandby,
    'beep': beep,
    'voice': voice,
    'scanMode': scanMode,
    'chADisplay': chADisplay,
    'chBDisplay': chBDisplay,
    'autoLock': autoLock,
    'chAWorkmode': chAWorkmode,
    'chBWorkmode': chBWorkmode,
    'powerOnDisplay': powerOnDisplay,
    'micGain': micGain,
    'currentBankA': currentBankA,
    'currentBankB': currentBankB,
    'bluetoothAudioGain': bluetoothAudioGain,
    'bluetoothMicGain': bluetoothMicGain,
    'callSign': callSign,
  };
}

class DtmfSettings {
  DtmfSettings();

  String localId = '100';
  int wordTime = 1;
  int idleTime = 1;
  List<String> groups = List.generate(15, (index) => '${101 + index}');
  List<String> groupNames = List.generate(15, (index) => '成员${index + 1}');

  DtmfSettings copy() => DtmfSettings.fromJson(toJson());

  factory DtmfSettings.fromJson(Map<String, dynamic> json) {
    final dtmf = DtmfSettings();
    dtmf.localId = json['localId'] as String? ?? dtmf.localId;
    dtmf.wordTime = json['wordTime'] as int? ?? dtmf.wordTime;
    dtmf.idleTime = json['idleTime'] as int? ?? dtmf.idleTime;
    dtmf.groups = (json['groups'] as List<dynamic>? ?? dtmf.groups)
        .map((item) => item.toString())
        .toList();
    dtmf.groupNames = (json['groupNames'] as List<dynamic>? ?? dtmf.groupNames)
        .map((item) => item.toString())
        .toList();
    return dtmf;
  }

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'wordTime': wordTime,
    'idleTime': idleTime,
    'groups': groups,
    'groupNames': groupNames,
  };
}

class FmSettings {
  FmSettings();

  int currentFreq = 904;
  List<int> channels = List.filled(30, 0);

  FmSettings copy() => FmSettings.fromJson(toJson());

  factory FmSettings.fromJson(Map<String, dynamic> json) {
    final fm = FmSettings();
    fm.currentFreq = json['currentFreq'] as int? ?? fm.currentFreq;
    fm.channels = (json['channels'] as List<dynamic>? ?? fm.channels)
        .map((item) => item as int)
        .toList();
    return fm;
  }

  Map<String, dynamic> toJson() => {
    'currentFreq': currentFreq,
    'channels': channels,
  };
}

class BootImageDraft {
  BootImageDraft();

  String name = '';
  String previewNote = '开发中：后续会接入图片选择、128x128 裁切、RGB565 转换和写图进度显示。';

  BootImageDraft copy() => BootImageDraft.fromJson(toJson());

  factory BootImageDraft.fromJson(Map<String, dynamic> json) {
    final image = BootImageDraft();
    image.name = json['name'] as String? ?? '';
    image.previewNote = json['previewNote'] as String? ?? image.previewNote;
    return image;
  }

  Map<String, dynamic> toJson() => {'name': name, 'previewNote': previewNote};
}

class RadioAppData {
  RadioAppData({
    required this.bankNames,
    required this.channels,
    required this.functions,
    required this.dtmf,
    required this.fm,
    required this.bootImage,
    required this.updatedAt,
  });

  factory RadioAppData.defaults() {
    return RadioAppData(
      bankNames: List.generate(8, (index) => '区域${index + 1}'),
      channels: List.generate(
        8,
        (_) => List.generate(64, (index) => Channel.empty(index + 1)),
      ),
      functions: RadioFunctionSettings(),
      dtmf: DtmfSettings(),
      fm: FmSettings(),
      bootImage: BootImageDraft(),
      updatedAt: DateTime.now(),
    );
  }

  List<String> bankNames;
  List<List<Channel>> channels;
  RadioFunctionSettings functions;
  DtmfSettings dtmf;
  FmSettings fm;
  BootImageDraft bootImage;
  DateTime updatedAt;

  String vfoA = '440.62500';
  String vfoB = '145.62500';
  String vfoAOffset = '00.0000';
  String vfoBOffset = '00.0000';
  String vfoARxTone = 'OFF';
  String vfoATxTone = 'OFF';
  String vfoBRxTone = 'OFF';
  String vfoBTxTone = 'OFF';
  Map<String, List<int>> rawBlocks = {};

  int get visibleChannelCount => channels
      .expand((item) => item)
      .where((channel) => channel.visible && channel.rxFreq.isNotEmpty)
      .length;

  bool get hasBackupContent => visibleChannelCount > 0 || rawBlocks.isNotEmpty;

  String get backupSignature {
    final payload = Map<String, dynamic>.from(toJson())..remove('updatedAt');
    return jsonEncode(payload);
  }

  RadioAppData copy() => RadioAppData.fromJson(toJson());

  factory RadioAppData.fromJson(Map<String, dynamic> json) =>
      RadioAppData(
          bankNames: (json['bankNames'] as List<dynamic>)
              .map((item) => item.toString())
              .toList(),
          channels: (json['channels'] as List<dynamic>)
              .map(
                (group) => (group as List<dynamic>)
                    .map(
                      (channel) =>
                          Channel.fromJson(channel as Map<String, dynamic>),
                    )
                    .toList(),
              )
              .toList(),
          functions: RadioFunctionSettings.fromJson(
            json['functions'] as Map<String, dynamic>,
          ),
          dtmf: DtmfSettings.fromJson(json['dtmf'] as Map<String, dynamic>),
          fm: FmSettings.fromJson(json['fm'] as Map<String, dynamic>),
          bootImage: BootImageDraft.fromJson(
            json['bootImage'] as Map<String, dynamic>,
          ),
          updatedAt: DateTime.parse(json['updatedAt'] as String),
        )
        ..vfoA = json['vfoA'] as String? ?? '440.62500'
        ..vfoB = json['vfoB'] as String? ?? '145.62500'
        ..vfoAOffset = json['vfoAOffset'] as String? ?? '00.0000'
        ..vfoBOffset = json['vfoBOffset'] as String? ?? '00.0000'
        ..vfoARxTone = json['vfoARxTone'] as String? ?? 'OFF'
        ..vfoATxTone = json['vfoATxTone'] as String? ?? 'OFF'
        ..vfoBRxTone = json['vfoBRxTone'] as String? ?? 'OFF'
        ..vfoBTxTone = json['vfoBTxTone'] as String? ?? 'OFF'
        ..rawBlocks = (json['rawBlocks'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(
            key,
            (value as List<dynamic>).map((item) => item as int).toList(),
          ),
        );

  Map<String, dynamic> toJson() => {
    'bankNames': bankNames,
    'channels': channels
        .map((group) => group.map((channel) => channel.toJson()).toList())
        .toList(),
    'functions': functions.toJson(),
    'dtmf': dtmf.toJson(),
    'fm': fm.toJson(),
    'bootImage': bootImage.toJson(),
    'updatedAt': updatedAt.toIso8601String(),
    'vfoA': vfoA,
    'vfoB': vfoB,
    'vfoAOffset': vfoAOffset,
    'vfoBOffset': vfoBOffset,
    'vfoARxTone': vfoARxTone,
    'vfoATxTone': vfoATxTone,
    'vfoBRxTone': vfoBRxTone,
    'vfoBTxTone': vfoBTxTone,
    'rawBlocks': rawBlocks,
  };
}

class RadioSnapshot {
  RadioSnapshot({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.data,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final RadioAppData data;

  factory RadioSnapshot.fromJson(Map<String, dynamic> json) => RadioSnapshot(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    data: RadioAppData.fromJson(json['data'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'data': data.toJson(),
  };
}

class RepeaterEntry {
  const RepeaterEntry({
    required this.id,
    this.region = '',
    this.province = '',
    this.provinceCode = 0,
    required this.city,
    this.cityCode = 0,
    this.area = '',
    required this.name,
    required this.kind,
    required this.rxFreq,
    this.txFreq = '',
    required this.offset,
    required this.toneText,
    this.txTone,
    this.rxTone,
    this.callSign,
    this.updatedAt = '',
    this.mode,
    this.remark,
    this.source,
    this.sourceUser,
    this.sourceCreatedAt,
  });

  final String id;
  final String region;
  final String province;
  final int provinceCode;
  final String city;
  final int cityCode;
  final String area;
  final String name;
  final String kind;
  final String rxFreq;
  final String txFreq;
  final String offset;
  final String toneText;
  final String? txTone;
  final String? rxTone;
  final String? callSign;
  final String updatedAt;
  final String? mode;
  final String? remark;
  final String? source;
  final String? sourceUser;
  final int? sourceCreatedAt;

  String get displayName =>
      callSign == null || callSign!.isEmpty ? name : '$name $callSign';

  String get locationText => [
    region,
    province,
    city,
  ].where((item) => item.trim().isNotEmpty).join(' / ');

  factory RepeaterEntry.fromJson(Map<String, dynamic> json) => RepeaterEntry(
    id: json['id']?.toString() ?? '',
    region: json['region']?.toString() ?? '',
    province: json['province']?.toString() ?? '',
    provinceCode: json['provinceCode'] as int? ?? 0,
    city: json['city']?.toString() ?? '',
    cityCode: json['cityCode'] as int? ?? 0,
    area: json['area']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    callSign: json['callSign']?.toString(),
    updatedAt: json['updatedAt']?.toString() ?? '',
    kind: json['kind']?.toString() ?? '',
    rxFreq: json['rxFreq']?.toString() ?? '',
    txFreq: json['txFreq']?.toString() ?? '',
    offset: json['offset']?.toString() ?? '',
    toneText: json['toneText']?.toString() ?? '',
    txTone: json['txTone']?.toString(),
    rxTone: json['rxTone']?.toString(),
    mode: json['mode']?.toString(),
    remark: json['remark']?.toString(),
    source: json['source']?.toString(),
    sourceUser: json['sourceUser']?.toString(),
    sourceCreatedAt: json['sourceCreatedAt'] as int?,
  );
}

class RepeaterProvinceGroup {
  const RepeaterProvinceGroup({
    required this.name,
    required this.code,
    required this.analogTotal,
    required this.digiTotal,
    this.municipality,
  });

  final String name;
  final int code;
  final int analogTotal;
  final int digiTotal;
  final bool? municipality;

  factory RepeaterProvinceGroup.fromJson(Map<String, dynamic> json) =>
      RepeaterProvinceGroup(
        name: json['name']?.toString() ?? '',
        code: json['code'] as int? ?? 0,
        analogTotal: json['analog_total'] as int? ?? 0,
        digiTotal: json['digi_total'] as int? ?? 0,
        municipality: json['municipality'] as bool?,
      );
}

class RepeaterRegionGroup {
  const RepeaterRegionGroup({required this.label, required this.children});

  final String label;
  final List<RepeaterProvinceGroup> children;

  factory RepeaterRegionGroup.fromJson(Map<String, dynamic> json) =>
      RepeaterRegionGroup(
        label: json['label']?.toString() ?? '',
        children: (json['children'] as List<dynamic>? ?? [])
            .map(
              (item) =>
                  RepeaterProvinceGroup.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
}

class RepeaterLibraryPackage {
  const RepeaterLibraryPackage({
    required this.source,
    required this.fetchedAt,
    required this.total,
    required this.regions,
    required this.repeaters,
  });

  final String source;
  final String fetchedAt;
  final int total;
  final List<RepeaterRegionGroup> regions;
  final List<RepeaterEntry> repeaters;

  factory RepeaterLibraryPackage.fromJson(Map<String, dynamic> json) =>
      RepeaterLibraryPackage(
        source: json['source']?.toString() ?? '',
        fetchedAt: json['fetchedAt']?.toString() ?? '',
        total: json['total'] as int? ?? 0,
        regions: (json['regions'] as List<dynamic>? ?? [])
            .map(
              (item) =>
                  RepeaterRegionGroup.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        repeaters: (json['repeaters'] as List<dynamic>? ?? [])
            .map((item) => RepeaterEntry.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class RepeaterLibraryLoader {
  static Future<RepeaterLibraryPackage> loadPackagedLibrary() async {
    final raw = await rootBundle.loadString('assets/data/hamcq-repeaters.json');
    return RepeaterLibraryPackage.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }
}

class ImportedChannelDraft {
  ImportedChannelDraft({
    required this.title,
    required this.sourceText,
    required this.rxFreq,
    required this.txFreq,
    required this.tone,
    required this.notes,
  });

  final String title;
  final String sourceText;
  final String rxFreq;
  final String txFreq;
  final String tone;
  final String notes;

  Channel makeChannel(int id) {
    return Channel(
      id: id,
      rxFreq: rxFreq,
      rxTone: tone == 'OFF' ? 'OFF' : tone,
      txFreq: txFreq,
      txTone: tone,
      txPower: 0,
      bandwidth: 0,
      scanAdd: 0,
      busyLock: 1,
      name: title.characters.take(12).toString(),
      visible: true,
    );
  }
}

class HelpTopic {
  const HelpTopic(this.title, this.detail);

  final String title;
  final String detail;
}

class ChangeLogEntry {
  const ChangeLogEntry(this.version, this.title, this.detail);

  final String version;
  final String title;
  final String detail;
}

class DemoData {
  static const repeaters = <RepeaterEntry>[
    RepeaterEntry(
      id: 'sz-br7jok',
      city: '深圳',
      name: '梧桐山',
      callSign: 'BR7JOK',
      kind: '模拟',
      rxFreq: '439.46250',
      offset: '-5.0',
      toneText: 'TSQ88.5',
    ),
    RepeaterEntry(
      id: 'sz-br7lzl',
      city: '深圳',
      name: '南山',
      callSign: 'BR7LZL',
      kind: '混合',
      rxFreq: '439.35000',
      offset: '-5.0',
      toneText: 'TSQ77.0',
    ),
    RepeaterEntry(
      id: 'zs-br7jbk',
      city: '中山',
      name: '粤桂中山',
      callSign: 'BR7JBK',
      kind: '模拟',
      rxFreq: '439.12500',
      offset: '-5.0',
      toneText: 'TSQ88.5',
    ),
    RepeaterEntry(
      id: 'hd-main',
      city: '惠东',
      name: '惠东总台',
      kind: '模拟',
      rxFreq: '439.97000',
      offset: '-8.0',
      toneText: 'TSQ88.5',
    ),
    RepeaterEntry(
      id: 'hd-sub',
      city: '惠东',
      name: '惠东台',
      kind: '模拟',
      rxFreq: '438.27000',
      offset: '-8.0',
      toneText: 'TSQ88.5',
    ),
    RepeaterEntry(
      id: 'hd-peak',
      city: '惠东',
      name: '高山台',
      kind: '模拟',
      rxFreq: '438.97000',
      offset: '-8.7',
      toneText: 'TSQ82.5',
    ),
  ];

  static const overviewSteps = [
    '1. 先点连接蓝牙，确认状态变成已连接。',
    '2. 先读频并保留自动备份，这样改错了也能恢复。',
    '3. 去信道页挑一条信道，先改接收频率、发射频率和亚音。',
    '4. 如果你不会手配参数，可以直接打开中继台库或者粘贴文本导入。',
    '5. 写频前再看一眼“正在操作的分组”，避免写到不是你想要的区域。',
  ];

  static const guideConcepts = [
    ('信道', '一个信道就是一组可收可发的无线电参数，最常见的是频率、亚音、功率和名称。'),
    ('区域', '区域可以理解成一个信道分组。你可以按用途拆成中继、车队、应急和打星。'),
    ('读频', '先把机器原本的数据读出来，再开始改，最稳。'),
    ('写频', '把 App 里的配置写回机器。正式写回前建议先留备份。'),
    ('CTCSS / DCS', '这是亚音和数字静噪。普通通联不会就先用 OFF。'),
    ('中继台', '中继通常会要求收发频率和亚音配套，直接用中继台库最省心。'),
  ];

  static const featureCards = [
    ('总览', '看连接状态、当前分组、备份数量和建议流程。'),
    ('信道', '编辑最常用的信道内容，也能从中继台库和粘贴文本导入。'),
    ('功能', '调整静噪、背光、VOX、扫描和双守等整机设置。'),
    ('工具', 'VFO、DTMF、FM、开机图、文件和蓝牙链路调试都在这里。'),
    ('教程', '把术语先讲清楚，再去操作对讲机。'),
    ('关于', '查看项目说明、免责声明、致谢和更新日志。'),
  ];

  static const settingsHelp = [
    HelpTopic('静噪等级 SQL', '值越高，越弱的杂音就越不容易被打开。听不到远台时可以先适当调低。'),
    HelpTopic('双守', '让机器同时盯住 A / B 两个区域。新手如果觉得切换太乱，可以先关闭。'),
    HelpTopic('自动锁', '一段时间不操作后自动锁键，避免误碰。发现机器按不动时要先看看是否被锁住。'),
    HelpTopic('A / B 工作模式', '信道模式就是从写好的信道里选；频率模式更像手动直输频率。'),
    HelpTopic('显示模式', '可以决定屏幕上优先显示名称、频率还是信道号。'),
  ];

  static const dtmfHelp = [
    HelpTopic('本机 ID', 'DTMF 设备识别号。需要联动呼叫时再填写，平时可以保留默认。'),
    HelpTopic('发码时长', '每个按键音持续多久。对方设备识别不稳时，可以把时长调长一点。'),
    HelpTopic('组呼列表', '把常用的 DTMF 编码先存下来，后面就不用每次手动敲。'),
  ];

  static const fmHelp = [
    HelpTopic('FM 广播', '这是收音机，不是业余电台信道。常用电台可以先写进记忆位。'),
    HelpTopic('当前频点', '例如 904 表示 90.4 MHz。'),
  ];

  static const updateLogs = [
    ChangeLogEntry(
      'v0.1',
      '原生移动端结构确定',
      'Android 版采用 Flutter，交互路径和 iOS 版保持一致，围绕新手流程重排页面结构。',
    ),
    ChangeLogEntry(
      'v0.2',
      '蓝牙链路骨架接通',
      '加入 FFE0 / FFE1 服务发现、通知监听、状态反馈和通信日志，为后续接入完整写频协议打底。',
    ),
    ChangeLogEntry('v0.3', '中继台与粘贴导入', '支持从内置中继台库直接带入，也支持从文字里识别频率、频差和亚音一键导入。'),
    ChangeLogEntry('v0.4', '备份与新手流程', '加入自动备份、手动备份、恢复入口和更适合第一次使用的页面说明。'),
  ];
}

class RadioChoices {
  static const power = ['高功率', '中功率', '低功率'];
  static const bandwidth = ['宽带', '窄带'];
  static const onOff = ['关闭', '开启'];
  static const scanMode = ['时间', '载波', '搜索'];
  static const workMode = ['信道模式', '频率模式'];
  static const displayMode = ['名称', '频率', '信道号'];
  static const autoLock = ['关闭', '5秒', '10秒', '15秒'];
  static const backlight = ['常亮', '5秒', '10秒', '20秒', '30秒'];
  static const pttId = ['关闭', 'BOT', 'EOT', 'BOT+EOT'];
}

class ToneLibrary {
  static const ctcss = [
    'OFF',
    '67.0',
    '69.3',
    '71.9',
    '74.4',
    '77.0',
    '79.7',
    '82.5',
    '85.4',
    '88.5',
    '91.5',
    '94.8',
    '97.4',
    '100.0',
    '103.5',
    '107.2',
    '110.9',
    '114.8',
    '118.8',
    '123.0',
    '127.3',
    '131.8',
    '136.5',
    '141.3',
    '146.2',
    '151.4',
    '156.7',
    '159.8',
    '162.2',
    '165.5',
    '167.9',
    '171.3',
    '173.8',
    '177.3',
    '179.9',
    '183.5',
    '186.2',
    '189.9',
    '192.8',
    '196.6',
    '199.5',
    '203.5',
    '206.5',
    '210.7',
    '218.1',
    '225.7',
    '229.1',
    '233.6',
    '241.8',
    '250.3',
    '254.1',
  ];

  static final dcs = _dcsCodesText.trim().split(RegExp(r'\s+'));
  static final choices = [...ctcss, ...dcs];

  static const _dcsCodesText = '''
D023N D025N D026N D031N D032N D036N D043N D047N D051N D053N D054N D065N
D071N D072N D073N D074N D114N D115N D116N D122N D125N D131N D132N D134N
D143N D145N D152N D155N D156N D162N D165N D172N D174N D205N D212N D223N
D225N D226N D243N D244N D245N D246N D251N D252N D255N D261N D263N D265N
D266N D271N D274N D306N D311N D315N D325N D331N D332N D343N D346N D351N
D356N D364N D365N D371N D411N D412N D413N D423N D431N D432N D445N D446N
D452N D454N D455N D462N D464N D465N D466N D503N D506N D516N D523N D526N
D532N D546N D565N D606N D612N D624N D627N D631N D632N D645N D654N D662N
D664N D703N D712N D723N D731N D732N D734N D743N D754N
D023I D025I D026I D031I D032I D036I D043I D047I D051I D053I D054I D065I
D071I D072I D073I D074I D114I D115I D116I D122I D125I D131I D132I D134I
D143I D145I D152I D155I D156I D162I D165I D172I D174I D205I D212I D223I
D225I D226I D243I D244I D245I D246I D251I D252I D255I D261I D263I D265I
D266I D271I D274I D306I D311I D315I D325I D331I D332I D343I D346I D351I
D356I D364I D365I D371I D411I D412I D413I D423I D431I D432I D445I D446I
D452I D454I D455I D462I D464I D465I D466I D503I D506I D516I D523I D526I
D532I D546I D565I D606I D612I D624I D627I D631I D632I D645I D654I D662I
D664I D703I D712I D723I D731I D732I D734I D743I D754I
''';
}

class ImportParser {
  static List<ImportedChannelDraft> parse(String source) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final drafts = <ImportedChannelDraft>[];
    String? pendingTitle;

    for (final line in lines) {
      if (_containsFrequency(line)) {
        final draft = _parseLine(line, pendingTitle);
        if (draft != null) {
          drafts.add(draft);
        }
        pendingTitle = null;
      } else {
        pendingTitle = line;
      }
    }

    if (drafts.isEmpty) {
      final draft = _parseLine(normalized.replaceAll('\n', ' '), null);
      if (draft != null) {
        drafts.add(draft);
      }
    }

    return drafts;
  }

  static ImportedChannelDraft? _parseLine(String line, String? titleHint) {
    final rx = _firstFrequency(line);
    if (rx == null) {
      return null;
    }
    final offset = _extractOffset(line);
    final tone = _extractTone(line) ?? 'OFF';
    return ImportedChannelDraft(
      title: _buildTitle(line, titleHint, rx),
      sourceText: line,
      rxFreq: rx,
      txFreq: _txFrequency(rx, offset),
      tone: tone,
      notes: _buildNotes(line, offset, tone),
    );
  }

  static bool _containsFrequency(String line) => _firstFrequency(line) != null;

  static String? _firstFrequency(String line) {
    final match = RegExp(
      r'\b(1\d{2}|[234]\d{2}|5[0-1]\d)\.\d{3,5}\b',
    ).firstMatch(line);
    return match?.group(0);
  }

  static String? _extractTone(String line) {
    final patterns = [
      RegExp(
        r'(?:亚音|T(?:SQ)?|CTCSS)\s*[:：]?\s*([0-9]{2,3}(?:\.[0-9])?)',
        caseSensitive: false,
      ),
      RegExp(r'([0-9]{2,3}(?:\.[0-9])?)\s*hz', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  static double? _extractOffset(String line) {
    final lower = line.toLowerCase();
    final down = RegExp(r'下差\s*([+-]?\d+(?:\.\d+)?)').firstMatch(lower);
    if (down != null) {
      return -(double.tryParse(down.group(1)!)?.abs() ?? 0);
    }
    final up = RegExp(r'上差\s*([+-]?\d+(?:\.\d+)?)').firstMatch(lower);
    if (up != null) {
      return double.tryParse(up.group(1)!);
    }
    final generic = RegExp(
      r'(?:偏移|差值|offset)\s*[:：]?\s*([+-]?\d+(?:\.\d+)?)',
    ).firstMatch(lower);
    if (generic != null) {
      return double.tryParse(generic.group(1)!);
    }
    final loose = RegExp(r'\b([+-]\d+(?:\.\d+)?)\b').firstMatch(lower);
    if (loose != null) {
      return double.tryParse(loose.group(1)!);
    }
    return null;
  }

  static String _txFrequency(String rx, double? offset) {
    final rxValue = double.tryParse(rx);
    if (rxValue == null || offset == null) {
      return rx;
    }
    return (rxValue + offset).toStringAsFixed(5);
  }

  static String _buildTitle(String line, String? titleHint, String rx) {
    if (titleHint != null && titleHint.trim().isNotEmpty) {
      return _cleanTitle(titleHint);
    }
    final stripped = line
        .replaceAll(rx, ' ')
        .replaceAll('亚音', ' ')
        .replaceAll('下差', ' ')
        .replaceAll('上差', ' ')
        .replaceAll('HT搜索', ' ')
        .trim();
    return stripped.isEmpty ? '导入信道' : _cleanTitle(stripped);
  }

  static String _cleanTitle(String value) {
    return value
        .replaceAll('：', ' ')
        .replaceAll(':', ' ')
        .split(RegExp(r'\s+'))
        .join(' ')
        .trim()
        .substring(
          0,
          min(
            16,
            value
                .replaceAll('：', ' ')
                .replaceAll(':', ' ')
                .split(RegExp(r'\s+'))
                .join(' ')
                .trim()
                .length,
          ),
        );
  }

  static String _buildNotes(String line, double? offset, String tone) {
    final parts = <String>[];
    if (offset != null) {
      parts.add('频差 ${offset.toStringAsFixed(1)}');
    }
    if (tone != 'OFF') {
      parts.add('亚音 $tone');
    }
    final upper = line.toUpperCase();
    if (upper.contains('C4FM')) {
      parts.add('包含 C4FM 标记');
    } else if (upper.contains('FM')) {
      parts.add('包含 FM 标记');
    }
    return parts.join(' · ');
  }
}

class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }
}

class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final background = primary ? const Color(0xFF0F9D8A) : Colors.white;
    final foreground = primary ? Colors.white : Colors.black87;

    return SizedBox(
      height: 48,
      child: FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class InfoStrip extends StatelessWidget {
  const InfoStrip({super.key, required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class JumpTile extends StatelessWidget {
  const JumpTile({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class HintTile extends StatelessWidget {
  const HintTile({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x140F9D8A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text),
    );
  }
}

class EmptyTile extends StatelessWidget {
  const EmptyTile({super.key, required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(detail, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class ChannelTile extends StatelessWidget {
  const ChannelTile({super.key, required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              'CH-${channel.id}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name.isEmpty ? '未命名信道' : channel.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'RX ${channel.rxFreq} · TX ${channel.txFreq}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SelectableChannelTile extends StatelessWidget {
  const SelectableChannelTile({
    super.key,
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  final Channel channel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0x1F0F9D8A) : const Color(0xFFF8FCFB),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                'CH-${channel.id}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name.isEmpty ? '未命名信道' : channel.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    channel.rxFreq.isEmpty
                        ? '空信道'
                        : 'RX ${channel.rxFreq} · TX ${channel.txFreq.isEmpty ? channel.rxFreq : channel.txFreq}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RepeaterTile extends StatelessWidget {
  const RepeaterTile({super.key, required this.repeater});

  final RepeaterEntry repeater;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  repeater.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    repeater.locationText.isEmpty
                        ? repeater.city
                        : repeater.locationText,
                    'RX ${repeater.rxFreq}',
                    if (repeater.txFreq.trim().isNotEmpty)
                      'TX ${repeater.txFreq}'
                    else
                      '差 ${repeater.offset}',
                    if (repeater.toneText.trim().isNotEmpty) repeater.toneText,
                  ].join(' · '),
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x140F9D8A),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              repeater.kind,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F9D8A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.positive});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: positive ? const Color(0x140F9D8A) : const Color(0x14FF8A00),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: positive ? const Color(0xFF0F9D8A) : const Color(0xFFFF8A00),
        ),
      ),
    );
  }
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.message});

  final NoticeMessage message;

  @override
  Widget build(BuildContext context) {
    final color = switch (message.tone) {
      NoticeTone.warning => const Color(0xFFFF8A00),
      NoticeTone.success => const Color(0xFF0F9D8A),
      NoticeTone.neutral => const Color(0xFF326BFF),
    };
    final icon = switch (message.tone) {
      NoticeTone.warning => Icons.warning_amber_rounded,
      NoticeTone.success => Icons.check_circle_rounded,
      NoticeTone.neutral => Icons.info_outline_rounded,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(message.text)),
        ],
      ),
    );
  }
}

class TransferProgressBanner extends StatelessWidget {
  const TransferProgressBanner({super.key, required this.store});

  final MobileStore store;

  @override
  Widget build(BuildContext context) {
    final value = store.transferProgressValue ?? 0;
    final percent = (value * 100).clamp(0, 100).round();

    return Material(
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x1F0F9D8A)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.sync_rounded,
                  size: 18,
                  color: Color(0xFF0F9D8A),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    store.transferProgressTitle.isEmpty
                        ? store.progressNote
                        : store.transferProgressTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    color: Color(0xFF0F9D8A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 7,
                backgroundColor: const Color(0x140F9D8A),
                color: const Color(0xFF0F9D8A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 12),
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class FormFieldCard extends StatelessWidget {
  const FormFieldCard({
    super.key,
    required this.title,
    required this.child,
    this.compact = false,
  });

  final String title;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: compact ? 12 : 14,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(detail, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class VfoEditor extends StatelessWidget {
  const VfoEditor({
    super.key,
    required this.title,
    required this.frequency,
    required this.offset,
    required this.rxTone,
    required this.txTone,
    required this.onFrequencyChanged,
    required this.onOffsetChanged,
    required this.onRxToneChanged,
    required this.onTxToneChanged,
  });

  final String title;
  final String frequency;
  final String offset;
  final String rxTone;
  final String txTone;
  final ValueChanged<String> onFrequencyChanged;
  final ValueChanged<String> onOffsetChanged;
  final ValueChanged<String> onRxToneChanged;
  final ValueChanged<String> onTxToneChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FormFieldCard(
                  title: '频率',
                  compact: true,
                  child: TextFormField(
                    key: ValueKey('$title-frequency-$frequency'),
                    initialValue: frequency,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '145.62500',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: onFrequencyChanged,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FormFieldCard(
                  title: '频差',
                  compact: true,
                  child: TextFormField(
                    key: ValueKey('$title-offset-$offset'),
                    initialValue: offset,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '00.0000',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: onOffsetChanged,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FormFieldCard(
                  title: '接收亚音',
                  compact: true,
                  child: DropdownButtonFormField<String>(
                    initialValue: rxTone,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: ToneLibrary.choices
                        .map(
                          (tone) => DropdownMenuItem<String>(
                            value: tone,
                            child: Text(tone),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => onRxToneChanged(value ?? 'OFF'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FormFieldCard(
                  title: '发射亚音',
                  compact: true,
                  child: DropdownButtonFormField<String>(
                    initialValue: txTone,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: ToneLibrary.choices
                        .map(
                          (tone) => DropdownMenuItem<String>(
                            value: tone,
                            child: Text(tone),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => onTxToneChanged(value ?? 'OFF'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BackupTile extends StatelessWidget {
  const BackupTile({
    super.key,
    required this.snapshot,
    required this.onRestore,
    required this.onDelete,
  });

  final RadioSnapshot snapshot;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onRestore,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FCFB),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('yyyy-MM-dd HH:mm').format(snapshot.createdAt),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '删除备份',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: onDelete,
            ),
            const Icon(Icons.restore_rounded),
          ],
        ),
      ),
    );
  }
}

class ShxBlock {
  const ShxBlock({required this.address, required this.payload});

  final int address;
  final Uint8List payload;
}

class ShxCodec {
  static const int framePayloadBytes = 64;
  static const int vfoAddress = 0x8000;
  static const int functionAddress = 0x9000;
  static const int bankNameAAddress = 0xa200;
  static const int bankNameBAddress = 0xa240;
  static const int fmAddress = 0xb000;

  static List<int> readWriteAddresses() {
    final addresses = <int>[];
    for (var address = 0; address < 0x4000; address += 0x40) {
      addresses.add(address);
    }
    addresses.addAll([vfoAddress, functionAddress]);
    for (var address = 0xa000; address <= 0xa100; address += 0x40) {
      addresses.add(address);
    }
    addresses.addAll([bankNameAAddress, bankNameBAddress, fmAddress]);
    return addresses;
  }

  static String addressLabel(int address) {
    if (address < 0x4000) {
      return '信道 ${address ~/ 0x40 * 2 + 1}-${address ~/ 0x40 * 2 + 2}';
    }
    if (address == vfoAddress) return 'VFO A/B';
    if (address == functionAddress) return '功能设置';
    if (address >= 0xa000 && address <= 0xa100) return 'DTMF';
    if (address == bankNameAAddress || address == bankNameBAddress) {
      return '区域名称';
    }
    if (address == fmAddress) return 'FM 收音机';
    return '0x${address.toRadixString(16).toUpperCase()}';
  }

  static Uint8List readFrame(int address) =>
      Uint8List.fromList([0x52, (address >> 8) & 0xff, address & 0xff, 0x40]);

  static Uint8List writeFrame(int address, Uint8List payload) {
    final frame = Uint8List(68);
    frame[0] = 0x57;
    frame[1] = (address >> 8) & 0xff;
    frame[2] = address & 0xff;
    frame[3] = 0x40;
    frame.setRange(4, 68, payload.take(64));
    return frame;
  }

  static void applyBlock(RadioAppData data, int address, Uint8List frame) {
    final payload = frame.length == 68
        ? Uint8List.fromList(frame.sublist(4))
        : Uint8List.fromList(frame);
    data.rawBlocks[_blockKey(address)] = payload.toList();
    if (address < 0x4000) {
      final flat = address ~/ 0x40 * 2;
      _setChannelByFlatIndex(
        data,
        flat,
        _decodeChannel(payload.sublist(0, 32), flat % 64 + 1, address),
      );
      _setChannelByFlatIndex(
        data,
        flat + 1,
        _decodeChannel(payload.sublist(32, 64), (flat + 1) % 64 + 1),
      );
      return;
    }
    if (address == vfoAddress) {
      _decodeVfo(data, payload.sublist(0, 32), true);
      _decodeVfo(data, payload.sublist(32, 64), false);
      return;
    }
    if (address == functionAddress) {
      final f = data.functions;
      f.sql = payload[0] % 10;
      f.backlight = payload[3] % 9;
      f.dualStandby = payload[4] % 2;
      f.beep = payload[6] % 2;
      f.voice = payload[7] % 2;
      f.scanMode = payload[10] % 3;
      f.chADisplay = payload[13] % 3;
      f.chBDisplay = payload[14] % 3;
      f.autoLock = payload[16] % 7;
      f.chAWorkmode = payload[26] & 0x0f;
      f.chBWorkmode = (payload[26] >> 4) & 0x0f;
      f.powerOnDisplay = payload[28] % 22;
      f.micGain = payload[34] % 3;
      f.currentBankA = payload[46] % 8;
      f.currentBankB = payload[47] % 8;
      f.bluetoothMicGain = payload[49] % 5;
      f.bluetoothAudioGain = payload[50] % 5;
      f.callSign = _decodeText(payload, 52, 6);
      return;
    }
    if (address >= 0xa000 && address <= 0xa100) {
      _decodeDtmf(data, address, payload);
      return;
    }
    if (address == bankNameAAddress || address == bankNameBAddress) {
      final start = address == bankNameAAddress ? 0 : 4;
      for (var index = 0; index < 4; index += 1) {
        data.bankNames[start + index] = _decodeText(payload, index * 16, 12);
      }
      return;
    }
    if (address == fmAddress) {
      data.fm.currentFreq = _decodeFm(payload, 0);
      for (var index = 0; index < 30; index += 1) {
        data.fm.channels[index] = _decodeFm(payload, 2 + index * 2);
      }
    }
  }

  static List<ShxBlock> bluetoothWriteBlocks(RadioAppData data) {
    final blocks = <ShxBlock>[];
    for (var address = 0; address < 0x4000; address += 0x80) {
      final first = _encodeBluetoothChannelBlock(data, address);
      final second = _encodeBluetoothChannelBlock(data, address + 0x40);
      if (first == null && second == null) continue;
      blocks.add(
        ShxBlock(
          address: address,
          payload:
              first ??
              _encodeBluetoothChannelBlock(data, address, includeEmpty: true)!,
        ),
      );
      blocks.add(
        ShxBlock(
          address: address + 0x40,
          payload:
              second ??
              _encodeBluetoothChannelBlock(
                data,
                address + 0x40,
                includeEmpty: true,
              )!,
        ),
      );
    }
    for (final address in readWriteAddresses().where(
      (address) => address >= 0x4000,
    )) {
      blocks.add(
        ShxBlock(address: address, payload: _encodeBlock(data, address)),
      );
    }
    return blocks;
  }

  static List<(ShxBlock, ShxBlock)> groupBluetoothWritePairs(
    List<ShxBlock> blocks,
  ) {
    if (blocks.length.isOdd) {
      blocks.add(blocks.last);
    }
    final pairs = <(ShxBlock, ShxBlock)>[];
    for (var index = 0; index < blocks.length; index += 2) {
      pairs.add((blocks[index], blocks[index + 1]));
    }
    return pairs;
  }

  static Uint8List _encodeBlock(RadioAppData data, int address) {
    if (address < 0x4000) {
      final payload = _basePayload(data, address, 0xff);
      final flat = address ~/ 0x40 * 2;
      payload.setRange(
        0,
        32,
        _encodeChannel(
          data.channels[flat ~/ 64][flat % 64],
          payload.sublist(0, 32),
          address,
        ),
      );
      payload.setRange(
        32,
        64,
        _encodeChannel(
          data.channels[(flat + 1) ~/ 64][(flat + 1) % 64],
          payload.sublist(32, 64),
        ),
      );
      return payload;
    }
    final payload = _basePayload(data, address, 0x00);
    if (address == vfoAddress) {
      payload.setRange(0, 32, _encodeVfo(data, true, payload.sublist(0, 32)));
      payload.setRange(
        32,
        64,
        _encodeVfo(data, false, payload.sublist(32, 64)),
      );
      return payload;
    }
    if (address == functionAddress) {
      final f = data.functions;
      payload[0] = f.sql;
      payload[3] = f.backlight;
      payload[4] = f.dualStandby;
      payload[6] = f.beep;
      payload[7] = f.voice;
      payload[10] = f.scanMode;
      payload[13] = f.chADisplay;
      payload[14] = f.chBDisplay;
      payload[16] = f.autoLock;
      payload[26] = f.chAWorkmode | (f.chBWorkmode << 4);
      payload[28] = f.powerOnDisplay;
      payload[34] = f.micGain;
      payload[46] = f.currentBankA;
      payload[47] = f.currentBankB;
      payload[49] = f.bluetoothMicGain;
      payload[50] = f.bluetoothAudioGain;
      payload.setRange(
        52,
        58,
        _encodeText(
          f.callSign.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), ''),
          6,
          0,
        ),
      );
      return payload;
    }
    if (address >= 0xa000 && address <= 0xa100) {
      return _encodeDtmf(data, address, payload);
    }
    if (address == bankNameAAddress || address == bankNameBAddress) {
      return _encodeBankNames(data, address, payload);
    }
    if (address == fmAddress) {
      payload.setRange(0, 2, _encodeFm(data.fm.currentFreq));
      for (var index = 0; index < 30; index += 1) {
        payload.setRange(
          2 + index * 2,
          4 + index * 2,
          _encodeFm(data.fm.channels[index]),
        );
      }
      return payload;
    }
    return payload;
  }

  static Uint8List? _encodeBluetoothChannelBlock(
    RadioAppData data,
    int address, {
    bool includeEmpty = false,
  }) {
    final flat = address ~/ 0x40 * 2;
    final first = data.channels[flat ~/ 64][flat % 64];
    final second = data.channels[(flat + 1) ~/ 64][(flat + 1) % 64];
    if (!includeEmpty &&
        first.rxFreq.trim().isEmpty &&
        second.rxFreq.trim().isEmpty) {
      return null;
    }
    final payload = _basePayload(data, address, 0xff);
    payload.setRange(
      0,
      32,
      first.rxFreq.trim().isEmpty
          ? _emptyChannel(payload.sublist(0, 32), address)
          : _encodeChannel(first, payload.sublist(0, 32), address),
    );
    payload.setRange(
      32,
      64,
      second.rxFreq.trim().isEmpty
          ? _emptyChannel(payload.sublist(32, 64))
          : _encodeChannel(second, payload.sublist(32, 64)),
    );
    return payload;
  }

  static Uint8List _basePayload(RadioAppData data, int address, int fill) {
    final raw = data.rawBlocks[_blockKey(address)];
    if (raw != null && raw.length == 64) return Uint8List.fromList(raw);
    return Uint8List(64)..fillRange(0, 64, fill);
  }

  static Uint8List _encodeChannel(
    Channel channel,
    Uint8List base, [
    int? address,
  ]) {
    if (channel.rxFreq.trim().isEmpty) {
      return Uint8List(32)..fillRange(0, 32, 0xff);
    }
    final usable =
        !_isHeaderPolluted(base, address) && _isValidBcdFrequency(base, 0);
    final payload = usable
        ? Uint8List.fromList(base)
        : (Uint8List(32)..fillRange(0, 32, 0xff));
    payload.setRange(0, 4, _encodeChannelFreq(channel.rxFreq));
    payload.setRange(
      4,
      8,
      _encodeChannelFreq(
        channel.txFreq.trim().isEmpty ? channel.rxFreq : channel.txFreq,
      ),
    );
    payload.setRange(8, 10, _encodeTone(channel.rxTone));
    payload.setRange(10, 12, _encodeTone(channel.txTone));
    payload[12] = channel.signalGroup;
    payload[13] = channel.pttId;
    payload[14] = channel.txPower;
    payload[15] =
        (usable ? payload[15] & 0x03 : 0) |
        (channel.bandwidth << 6) |
        (channel.busyLock << 3) |
        (channel.scanAdd << 2);
    if (channel.name.trim().isNotEmpty) {
      payload.setRange(
        20,
        32,
        _encodeText(
          channel.name,
          12,
          payload.sublist(20, 32).contains(0) ? 0 : 0xff,
        ),
      );
    }
    return payload;
  }

  static Channel _decodeChannel(Uint8List payload, int id, [int? address]) {
    if (payload[0] == 0xff ||
        payload[1] == 0xff ||
        payload[3] == 0 ||
        _isHeaderPolluted(payload, address) ||
        !_isValidBcdFrequency(payload, 0)) {
      return Channel.empty(id);
    }
    return Channel(
      id: id,
      rxFreq: _decodeChannelFreq(payload, 0),
      txFreq: payload[4] == 0xff || payload[5] == 0xff
          ? ''
          : _decodeChannelFreq(payload, 4),
      rxTone: _decodeTone(payload, 8),
      txTone: _decodeTone(payload, 10),
      signalGroup: payload[12] % 20,
      pttId: payload[13] % 4,
      txPower: payload[14] % 3,
      bandwidth: (payload[15] >> 6) & 1,
      busyLock: (payload[15] >> 3) & 1,
      scanAdd: (payload[15] >> 2) & 1,
      name: payload[20] == 0xff ? '' : _decodeText(payload, 20, 12),
      visible: true,
    );
  }

  static Uint8List _emptyChannel(Uint8List base, [int? address]) {
    if (_isHeaderPolluted(base, address) || !_isValidBcdFrequency(base, 0)) {
      return Uint8List(32)..fillRange(0, 32, 0xff);
    }
    return Uint8List.fromList(base);
  }

  static bool _isHeaderPolluted(Uint8List payload, [int? address]) {
    if (payload.length < 4 || payload[0] != 0x57 || payload[3] != 0x40) {
      return false;
    }
    final headerAddress = (payload[1] << 8) | payload[2];
    if (headerAddress < 0x4000 && headerAddress % 0x40 == 0) return true;
    return address != null && headerAddress == address;
  }

  static bool _isValidBcdFrequency(Uint8List payload, int offset) {
    if (payload.length < offset + 4) return false;
    for (var index = offset; index < offset + 4; index += 1) {
      if ((payload[index] & 0x0f) > 9 || ((payload[index] >> 4) & 0x0f) > 9) {
        return false;
      }
    }
    final freq = double.tryParse(_decodeChannelFreq(payload, offset));
    return freq != null && freq >= 100 && freq < 520;
  }

  static Uint8List _encodeChannelFreq(String value) {
    final bytes = Uint8List.fromList([0xff, 0xff, 0xff, 0xff]);
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < 100 || parsed >= 520) return bytes;
    var numeric = (parsed * 100000).round();
    numeric = (numeric ~/ 125) * 125;
    for (var index = 0; index < 4; index += 1) {
      final pair = numeric % 100;
      numeric ~/= 100;
      bytes[index] = (((pair ~/ 10) << 4) | (pair % 10)) & 0xff;
    }
    return bytes;
  }

  static String _decodeChannelFreq(Uint8List payload, int offset) {
    var numeric = 0;
    for (var index = 3; index >= 0; index -= 1) {
      final pair =
          ((payload[offset + index] >> 4) & 0x0f) * 10 +
          (payload[offset + index] & 0x0f);
      numeric = numeric * 100 + pair;
    }
    final text = numeric.toString().padLeft(8, '0');
    return '${text.substring(0, 3)}.${text.substring(3)}';
  }

  static Uint8List _encodeTone(String value) {
    final bytes = Uint8List(2);
    if (value.isEmpty || value == 'OFF') return bytes;
    if (value.startsWith('D')) {
      final index = ToneLibrary.dcs.indexOf(value);
      bytes[0] = index >= 0 ? index + 1 : 0;
      bytes[1] = 0;
      return bytes;
    }
    final numeric = int.tryParse(value.replaceAll('.', ''));
    if (numeric == null) return bytes;
    bytes[0] = numeric & 0xff;
    bytes[1] = (numeric >> 8) & 0xff;
    return bytes;
  }

  static String _decodeTone(Uint8List payload, int offset) {
    final first = payload[offset];
    final second = payload[offset + 1];
    if (second == 0) {
      if (first > 0 && first <= ToneLibrary.dcs.length) {
        return ToneLibrary.dcs[first - 1];
      }
      return 'OFF';
    }
    if (first != 0 && first != 0xff) {
      final text = ((second << 8) + first).toString();
      return '${text.substring(0, text.length - 1)}.${text.substring(text.length - 1)}';
    }
    return 'OFF';
  }

  static Uint8List _encodeVfo(RadioAppData data, bool sideA, Uint8List base) {
    final payload = Uint8List.fromList(base);
    payload.setRange(0, 8, _encodeVfoFreq(sideA ? data.vfoA : data.vfoB));
    payload.setRange(
      8,
      10,
      _encodeTone(sideA ? data.vfoARxTone : data.vfoBRxTone),
    );
    payload.setRange(
      10,
      12,
      _encodeTone(sideA ? data.vfoATxTone : data.vfoBTxTone),
    );
    payload.setRange(
      20,
      27,
      _encodeOffset(sideA ? data.vfoAOffset : data.vfoBOffset),
    );
    return payload;
  }

  static void _decodeVfo(RadioAppData data, Uint8List payload, bool sideA) {
    if (sideA) {
      data.vfoA = _decodeVfoFreq(payload);
      data.vfoARxTone = _decodeTone(payload, 8);
      data.vfoATxTone = _decodeTone(payload, 10);
      data.vfoAOffset = _decodeOffset(payload, 20);
    } else {
      data.vfoB = _decodeVfoFreq(payload);
      data.vfoBRxTone = _decodeTone(payload, 8);
      data.vfoBTxTone = _decodeTone(payload, 10);
      data.vfoBOffset = _decodeOffset(payload, 20);
    }
  }

  static Uint8List _encodeVfoFreq(String value) {
    final bytes = Uint8List(8)..fillRange(0, 8, 0xff);
    final parsed = double.tryParse(value);
    if (parsed == null) return bytes;
    var numeric = (parsed * 100000).round();
    for (var index = 7; index >= 0; index -= 1) {
      bytes[index] = numeric % 10;
      numeric ~/= 10;
    }
    return bytes;
  }

  static String _decodeVfoFreq(Uint8List payload) {
    final text = List.generate(8, (index) => '${payload[index] % 10}').join();
    return '${text.substring(0, 3)}.${text.substring(3)}';
  }

  static Uint8List _encodeOffset(String value) {
    final parts = value.split('.');
    var numeric =
        (int.tryParse(parts.first) ?? 0) * 10000 +
        int.parse(
          ((parts.length > 1 ? parts[1] : '').padRight(4, '0')).substring(0, 4),
        );
    final bytes = Uint8List(7)..fillRange(0, 7, 0xff);
    for (var index = 6; index >= 0; index -= 1) {
      bytes[index] = numeric % 10;
      numeric ~/= 10;
    }
    return bytes;
  }

  static String _decodeOffset(Uint8List payload, int offset) {
    final text = List.generate(
      7,
      (index) => '${payload[offset + index] % 10}',
    ).join();
    return '${text.substring(0, 3)}.${text.substring(3)}';
  }

  static Uint8List _encodeBankNames(
    RadioAppData data,
    int address,
    Uint8List base,
  ) {
    final hasRawBlock = data.rawBlocks[_blockKey(address)]?.length == 64;
    final payload = hasRawBlock
        ? Uint8List.fromList(base)
        : (Uint8List(64)..fillRange(0, 64, 0xff));
    final start = address == bankNameAAddress ? 0 : 4;
    for (var index = 0; index < 4; index += 1) {
      final offset = index * 16;
      final name = data.bankNames[start + index].trim();
      final currentName = hasRawBlock ? _decodeText(payload, offset, 12) : '';
      if (hasRawBlock && (name.isEmpty || name == currentName)) continue;
      if (name.isEmpty) continue;
      payload.setRange(
        offset,
        offset + 12,
        _encodeText(
          name,
          12,
          payload.sublist(offset, offset + 12).contains(0) ? 0 : 0xff,
        ),
      );
      payload.fillRange(offset + 12, offset + 16, 0xff);
    }
    return payload;
  }

  static Uint8List _encodeDtmf(RadioAppData data, int address, Uint8List base) {
    final payload = Uint8List.fromList(base);
    void writeWord(int offset, String word) {
      for (var index = 0; index < min(6, word.length); index += 1) {
        final value = '0123456789ABCD*#'.indexOf(word[index].toUpperCase());
        if (value >= 0) payload[offset + index] = value;
      }
    }

    switch (address) {
      case 0xa000:
        writeWord(0, data.dtmf.localId);
        payload[7] = data.dtmf.wordTime;
        payload[8] = data.dtmf.idleTime;
        writeWord(32, data.dtmf.groups[0]);
        writeWord(48, data.dtmf.groups[1]);
        break;
      case 0xa040:
        for (var index = 0; index < 4; index += 1) {
          writeWord(index * 16, data.dtmf.groups[index + 2]);
        }
        break;
      case 0xa080:
        for (var index = 0; index < 4; index += 1) {
          writeWord(index * 16, data.dtmf.groups[index + 6]);
        }
        break;
      case 0xa0c0:
        for (var index = 0; index < 4; index += 1) {
          writeWord(index * 16, data.dtmf.groups[index + 10]);
        }
        break;
      case 0xa100:
        writeWord(0, data.dtmf.groups[14]);
        break;
    }
    return payload;
  }

  static void _decodeDtmf(RadioAppData data, int address, Uint8List payload) {
    String readWord(int offset) {
      var text = '';
      for (
        var index = 0;
        index < 6 && payload[offset + index] != 0xff;
        index += 1
      ) {
        text += '0123456789ABCD*#'[payload[offset + index] % 16];
      }
      return text;
    }

    switch (address) {
      case 0xa000:
        data.dtmf.localId = readWord(0);
        data.dtmf.wordTime = payload[7] % 16;
        data.dtmf.idleTime = payload[8] % 16;
        data.dtmf.groups[0] = readWord(32);
        data.dtmf.groups[1] = readWord(48);
        break;
      case 0xa040:
        for (var index = 0; index < 4; index += 1) {
          data.dtmf.groups[index + 2] = readWord(index * 16);
        }
        break;
      case 0xa080:
        for (var index = 0; index < 4; index += 1) {
          data.dtmf.groups[index + 6] = readWord(index * 16);
        }
        break;
      case 0xa0c0:
        for (var index = 0; index < 4; index += 1) {
          data.dtmf.groups[index + 10] = readWord(index * 16);
        }
        break;
      case 0xa100:
        data.dtmf.groups[14] = readWord(0);
        break;
    }
  }

  static Uint8List _encodeFm(int value) => Uint8List.fromList([
    value > 0 ? value & 0xff : 0,
    value > 0 ? (value >> 8) & 0xff : 0,
  ]);

  static int _decodeFm(Uint8List payload, int offset) {
    if (payload[offset] == 0xff || payload[offset + 1] == 0xff) return 0;
    final value = payload[offset] + (payload[offset + 1] << 8);
    return value >= 650 && value <= 1080 ? value : 0;
  }

  static Uint8List _encodeText(String input, int maxBytes, int fill) {
    final bytes = Uint8List(maxBytes)..fillRange(0, maxBytes, fill);
    var cursor = 0;
    for (final char in input.trim().characters) {
      final encoded = _encodeRadioChar(char);
      if (cursor + encoded.length > maxBytes) {
        break;
      }
      bytes.setRange(cursor, cursor + encoded.length, encoded);
      cursor += encoded.length;
    }
    return bytes;
  }

  static String _decodeText(Uint8List payload, int offset, int maxBytes) {
    final out = <int>[];
    for (var index = 0; index < maxBytes; index += 1) {
      final value = payload[offset + index];
      if (value == 0 || value == 0xff) break;
      out.add(value);
    }
    if (out.isEmpty) return '';
    try {
      return gbk_bytes.decode(out).trim();
    } catch (_) {
      return utf8.decode(out, allowMalformed: true).trim();
    }
  }

  static List<int> _encodeRadioChar(String char) {
    if (char.isEmpty) return const [];
    try {
      final encoded = gbk_bytes.encode(char);
      if (encoded.isNotEmpty &&
          encoded.every((byte) => byte >= 0 && byte <= 0xff)) {
        return encoded;
      }
    } catch (_) {
      // Fall through to a protocol-safe replacement byte.
    }
    return const [0x3f];
  }

  static void _setChannelByFlatIndex(
    RadioAppData data,
    int flat,
    Channel channel,
  ) {
    data.channels[flat ~/ 64][flat % 64] = channel;
  }

  static String _blockKey(int address) =>
      address.toRadixString(16).toUpperCase().padLeft(4, '0');
}

class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        Text(subtitle, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }
}
