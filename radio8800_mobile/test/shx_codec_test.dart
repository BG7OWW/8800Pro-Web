import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:radio8800_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts with an empty codeplug by default', () {
    final data = RadioAppData.defaults();

    expect(data.visibleChannelCount, 0);
    expect(data.hasBackupContent, isFalse);
  });

  test('preserves Chinese channel and bank names in radio text fields', () {
    final data = RadioAppData.defaults();
    data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '439.46250',
      txFreq: '434.46250',
      name: '梧桐山',
      visible: true,
    );
    data.bankNames[0] = '区域一ABC';

    final blocks = ShxCodec.bluetoothWriteBlocks(data);
    final channelBlock = blocks.firstWhere((block) => block.address == 0x0000);
    final bankNameBlock = blocks.firstWhere(
      (block) => block.address == ShxCodec.bankNameAAddress,
    );

    final decoded = RadioAppData.defaults();
    ShxCodec.applyBlock(decoded, channelBlock.address, channelBlock.payload);
    ShxCodec.applyBlock(decoded, bankNameBlock.address, bankNameBlock.payload);

    expect(decoded.channels[0][0].name, '梧桐山');
    expect(decoded.bankNames[0], '区域一ABC');
  });

  test('fills empty bank name slots with FF when no raw block exists', () {
    final data = RadioAppData.defaults();
    data.bankNames[1] = '';

    final block = ShxCodec.bluetoothWriteBlocks(
      data,
    ).firstWhere((item) => item.address == ShxCodec.bankNameAAddress);
    final emptySlot = block.payload.sublist(16, 28);

    expect(emptySlot.every((byte) => byte == 0xff), isTrue);
  });

  test('encodes and decodes DCS tones like the web codec', () {
    final data = RadioAppData.defaults();
    data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '439.46250',
      txFreq: '434.46250',
      rxTone: 'D023N',
      txTone: 'D754I',
      visible: true,
    );

    final block = ShxCodec.bluetoothWriteBlocks(
      data,
    ).firstWhere((item) => item.address == 0x0000);
    expect(block.payload[8], 1);
    expect(block.payload[9], 0);
    expect(block.payload[10], ToneLibrary.dcs.indexOf('D754I') + 1);
    expect(block.payload[11], 0);

    final decoded = RadioAppData.defaults();
    ShxCodec.applyBlock(decoded, block.address, block.payload);
    expect(decoded.channels[0][0].rxTone, 'D023N');
    expect(decoded.channels[0][0].txTone, 'D754I');
  });

  test('preserves DTMF PTT ID through json and radio blocks', () {
    final data = RadioAppData.defaults();
    data.dtmf.pttId = 3;
    data.dtmf.wordTime = 5;
    data.dtmf.idleTime = 7;

    final restored = RadioAppData.fromJson(data.toJson());
    expect(restored.dtmf.pttId, 3);

    final block = ShxCodec.bluetoothWriteBlocks(
      data,
    ).firstWhere((item) => item.address == 0xa000);
    expect(block.payload[6], 3);
    expect(block.payload[7], 5);
    expect(block.payload[8], 7);

    final decoded = RadioAppData.defaults();
    ShxCodec.applyBlock(decoded, block.address, block.payload);
    expect(decoded.dtmf.pttId, 3);
    expect(decoded.dtmf.wordTime, 5);
    expect(decoded.dtmf.idleTime, 7);
  });

  test('backup signatures ignore timestamp changes', () {
    final data = RadioAppData.defaults();
    expect(data.hasBackupContent, isFalse);

    data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '439.46250',
      txFreq: '434.46250',
      visible: true,
    );
    final before = data.backupSignature;
    data.updatedAt = data.updatedAt.add(const Duration(minutes: 5));

    expect(data.hasBackupContent, isTrue);
    expect(data.backupSignature, before);
  });

  test('copies and pastes channels while keeping target id', () {
    final store = MobileStore();
    store.data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '439.46250',
      txFreq: '434.46250',
      name: '梧桐山',
      visible: true,
    );

    store.selectChannel(1);
    store.copyCurrentChannel();
    store.selectChannel(2);
    store.pasteToCurrentChannel();

    expect(store.data.channels[0][1].id, 2);
    expect(store.data.channels[0][1].rxFreq, '439.46250');
    expect(store.data.channels[0][1].name, '梧桐山');
  });

  test('deletes a channel and shifts following channels up', () {
    final store = MobileStore();
    store.data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '430.00000',
      visible: true,
    );
    store.data.channels[0][1] = Channel(
      id: 2,
      rxFreq: '431.00000',
      visible: true,
    );
    store.data.channels[0][2] = Channel(
      id: 3,
      rxFreq: '432.00000',
      visible: true,
    );

    store.selectChannel(2);
    store.deleteCurrentChannelAndShift();

    expect(store.data.channels[0][0].id, 1);
    expect(store.data.channels[0][1].id, 2);
    expect(store.data.channels[0][1].rxFreq, '432.00000');
    expect(store.data.channels[0].last.id, 64);
    expect(store.data.channels[0].last.visible, isFalse);
  });

  test('compacts active channels to the front of the selected bank', () {
    final store = MobileStore();
    store.data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '430.00000',
      visible: true,
    );
    store.data.channels[0][3] = Channel(
      id: 4,
      rxFreq: '433.00000',
      visible: true,
    );
    store.data.channels[0][7] = Channel(
      id: 8,
      rxFreq: '437.00000',
      visible: true,
    );

    store.compactCurrentBank();

    expect(store.data.channels[0][0].id, 1);
    expect(store.data.channels[0][0].rxFreq, '430.00000');
    expect(store.data.channels[0][1].id, 2);
    expect(store.data.channels[0][1].rxFreq, '433.00000');
    expect(store.data.channels[0][2].id, 3);
    expect(store.data.channels[0][2].rxFreq, '437.00000');
    expect(store.data.channels[0][3].visible, isFalse);
  });

  test('updates bank names and rejects empty names', () {
    final store = MobileStore();

    store.updateBankName(0, ' 中继台区域123456789 ');

    expect(store.data.bankNames[0], '中继台区域1234567');
    expect(store.notice?.text, '已保存区域 1 名称');

    store.updateBankName(0, '   ');

    expect(store.data.bankNames[0], '中继台区域1234567');
    expect(store.notice?.text, '区域名称不能为空');
  });

  test('parses the packaged HamCQ repeater library', () {
    final raw = File('assets/data/hamcq-repeaters.json').readAsStringSync();
    final package = RepeaterLibraryPackage.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );

    expect(package.total, greaterThan(500));
    expect(package.repeaters.length, package.total);
    expect(package.regions, isNotEmpty);
    expect(package.repeaters.first.rxFreq, isNotEmpty);
  });

  test(
    'applies repeater tx frequency and explicit tones from library data',
    () {
      final store = MobileStore();
      final entry = RepeaterEntry(
        id: 'test',
        region: '7 区',
        province: '广东省',
        city: '深圳',
        name: '测试台',
        kind: '模拟',
        rxFreq: '439.46250',
        txFreq: '434.46250',
        offset: '-5.00000',
        toneText: 'T88.5 / TSQ88.5',
        txTone: '88.5',
        rxTone: '88.5',
      );

      store.applyRepeater(entry);

      final channel = store.data.channels[0][0];
      expect(channel.rxFreq, '439.46250');
      expect(channel.txFreq, '434.46250');
      expect(channel.rxTone, '88.5');
      expect(channel.txTone, '88.5');
      expect(channel.scanAdd, 1);
      expect(channel.busyLock, 1);
    },
  );

  test('deletes a selected backup snapshot', () {
    final store = MobileStore();
    store.backups.add(
      RadioSnapshot(
        id: 'a',
        title: '手动备份',
        createdAt: DateTime(2026, 6, 18),
        data: RadioAppData.defaults(),
      ),
    );

    store.deleteBackup('a');

    expect(store.backups, isEmpty);
    expect(store.notice?.text, contains('已删除备份'));
  });

  test('clears logs and leaves a clear marker', () {
    final store = MobileStore();
    store.logs.addAll(['old 1', 'old 2']);

    store.clearLogs();

    expect(store.logs.length, 1);
    expect(store.logs.first, contains('日志已清空'));
    expect(store.notice?.text, '日志已清空');
  });

  test(
    'save actions explain that radio transfer still needs write frequency',
    () {
      final store = MobileStore();

      store.saveFunctionSettings();
      expect(store.notice?.text, contains('回到总览页面点击写频'));

      store.saveVfoSettings();
      expect(store.notice?.text, contains('回到总览页面写频'));

      store.saveDtmfSettings();
      expect(store.notice?.text, contains('回到总览页面写频'));

      store.saveFmSettings();
      expect(store.notice?.text, contains('回到总览页面写频'));
    },
  );

  test('formats and parses FM frequencies as MHz drafts', () {
    expect(FmFrequency.formatDraft(904), '90.4');
    expect(FmFrequency.formatDraft(0), '');

    expect(FmFrequency.parseDraft('90.4'), 904);
    expect(FmFrequency.parseDraft('90.4MHz'), 904);
    expect(FmFrequency.parseDraft('90，4ＭＨＺ'), 904);
    expect(FmFrequency.parseDraft('76.0'), 760);
    expect(FmFrequency.parseDraft('108.0'), 1080);

    expect(FmFrequency.parseDraft(''), isNull);
    expect(FmFrequency.parseDraft('90.'), isNull);
    expect(FmFrequency.parseDraft('75.9'), isNull);
    expect(FmFrequency.parseDraft('108.1'), isNull);
  });

  test('edits FM current frequency and memory slots', () {
    final store = MobileStore();

    store.setFmCurrentFromDraft('90.4MHz');
    expect(store.data.fm.currentFreq, 904);

    store.stepFmCurrent(1);
    expect(store.data.fm.currentFreq, 905);

    store.stepFmCurrent(-200);
    expect(store.data.fm.currentFreq, 760);

    store.saveCurrentFmToMemory(0);
    expect(store.data.fm.channels[0], 760);

    store.setFmMemoryFromDraft(1, '98。8');
    expect(store.data.fm.channels[1], 988);

    store.loadFmMemory(1);
    expect(store.data.fm.currentFreq, 988);

    store.clearFmMemory(1);
    expect(store.data.fm.channels[1], 0);
  });

  test('reconnecting link state reports retry progress', () {
    final state = LinkState.reconnecting(2);

    expect(state.isConnected, isFalse);
    expect(state.isBusy, isTrue);
    expect(state.label, '正在重连 (2/3)');
  });

  test('disconnected and connected link states are not busy', () {
    expect(const LinkState.disconnected().isBusy, isFalse);
    expect(const LinkState.connected('蓝牙已连接').isBusy, isFalse);
    expect(const LinkState.scanning().isBusy, isTrue);
  });
}
